import { createClient } from "npm:@supabase/supabase-js@^2.95.0";
import { corsHeaders } from "npm:@supabase/supabase-js@^2.95.0/cors";

const responseHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json; charset=utf-8",
};

function jsonResponse(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...responseHeaders, ...extraHeaders },
  });
}

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isIsoDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}

function readBearerJwt(authorization) {
  if (typeof authorization !== "string") return null;

  const match = authorization.match(/^Bearer\s+(\S+)$/i);
  if (!match) return null;

  const token = match[1];
  return token.split(".").length === 3 ? token : null;
}

function optionalInteger(
  value,
  fieldName,
  minimum,
  maximum = null,
) {
  if (value === undefined || value === null) {
    return { value: null };
  }

  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < minimum
  ) {
    return {
      error: `${fieldName} must be a safe integer greater than or equal to ${minimum}.`,
    };
  }

  if (maximum !== null && value > maximum) {
    return {
      error: `${fieldName} must be less than or equal to ${maximum}.`,
    };
  }

  return { value };
}

function validateInput(
  input,
) {
  if (
    typeof input.need !== "string" ||
    input.need.trim().length === 0 ||
    input.need.length > 500
  ) {
    return { error: "need is required and must not exceed 500 characters." };
  }

  if (!isIsoDate(input.check_in_date) || !isIsoDate(input.check_out_date)) {
    return {
      error: "check_in_date and check_out_date must use YYYY-MM-DD format.",
    };
  }

  const today = new Date().toISOString().slice(0, 10);
  if (input.check_in_date < today) {
    return { error: "check_in_date cannot be in the past." };
  }

  if (input.check_out_date <= input.check_in_date) {
    return { error: "check_out_date must be after check_in_date." };
  }

  const guests = optionalInteger(input.guests, "guests", 1, 2_147_483_647);
  if ("error" in guests || guests.value === null) {
    return { error: "error" in guests ? guests.error : "guests is required." };
  }

  const branchId = optionalInteger(input.branch_id, "branch_id", 1);
  if ("error" in branchId) return { error: branchId.error };

  const roomTypeId = optionalInteger(input.room_type_id, "room_type_id", 1);
  if ("error" in roomTypeId) return { error: roomTypeId.error };

  const minPrice = optionalInteger(input.min_price, "min_price", 0);
  if ("error" in minPrice) return { error: minPrice.error };

  const maxPrice = optionalInteger(input.max_price, "max_price", 0);
  if ("error" in maxPrice) return { error: maxPrice.error };

  if (
    minPrice.value !== null &&
    maxPrice.value !== null &&
    minPrice.value > maxPrice.value
  ) {
    return { error: "min_price cannot be greater than max_price." };
  }

  return {
    data: {
      need: input.need.trim(),
      checkInDate: input.check_in_date,
      checkOutDate: input.check_out_date,
      guests: guests.value,
      branchId: branchId.value,
      roomTypeId: roomTypeId.value,
      minPrice: minPrice.value,
      maxPrice: maxPrice.value,
    },
  };
}

function toGeminiRoomMetadata(room) {
  return {
    room_id: room.room_id,
    branch_name: room.branch_name,
    branch_city: room.branch_city,
    room_type_name: room.room_type_name,
    room_type_capacity: room.room_type_capacity,
    room_type_bed_type: room.room_type_bed_type,
    room_type_area_m2: room.room_type_area_m2,
    room_number: room.room_number,
    room_name: room.room_name,
    room_description: room.room_description,
    price_per_night: room.price_per_night,
  };
}

function readGeminiText(responseBody) {
  const parts = responseBody?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return null;

  const text = parts
    .map((part) => typeof part?.text === "string" ? part.text : "")
    .join("")
    .trim();
  return text || null;
}

function mergeValidatedRankings(parsed, candidates) {
  if (!isPlainObject(parsed) || !Array.isArray(parsed.rankings)) {
    return null;
  }

  const candidateById = new Map(
    candidates.map((room) => [String(room.room_id), room]),
  );
  const seenRoomIds = new Set();
  const recommendations = [];

  for (const ranking of parsed.rankings) {
    if (recommendations.length >= 10) break;
    if (!isPlainObject(ranking)) continue;
    if (!Number.isSafeInteger(ranking.room_id) || ranking.room_id < 1) continue;

    const roomId = String(ranking.room_id);
    const reason = typeof ranking.reason === "string"
      ? ranking.reason.trim()
      : "";
    if (
      !candidateById.has(roomId) ||
      seenRoomIds.has(roomId) ||
      reason.length === 0 ||
      reason.length > 200
    ) {
      continue;
    }

    seenRoomIds.add(roomId);
    recommendations.push({
      ...candidateById.get(roomId),
      ai_reason: reason,
    });
  }

  return recommendations;
}

async function rankCandidatesWithGemini(
  need,
  candidates,
  apiKey,
  configuredModel,
) {
  const model = configuredModel.replace(/^models\//, "");
  if (!/^[a-zA-Z0-9._-]+$/.test(model)) {
    throw new Error("invalid_gemini_model");
  }

  const prompt = [
    "Rank the supplied hotel rooms for the travel need.",
    "Use only room_id values present in candidateRooms.",
    "Return at most 10 unique rooms, best match first.",
    "Give each room one concise reason of at most 160 characters.",
    "Do not invent room facts and do not include any additional fields.",
    JSON.stringify({
      need,
      candidateRooms: candidates.map(toGeminiRoomMetadata),
    }),
  ].join("\n");

  const geminiResponse = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${
      encodeURIComponent(model)
    }:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [{ text: prompt }],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              rankings: {
                type: "ARRAY",
                maxItems: 10,
                items: {
                  type: "OBJECT",
                  properties: {
                    room_id: { type: "INTEGER" },
                    reason: { type: "STRING" },
                  },
                  required: ["room_id", "reason"],
                },
              },
            },
            required: ["rankings"],
          },
        },
      }),
      signal: AbortSignal.timeout(20_000),
    },
  );

  if (!geminiResponse.ok) {
    console.error("Gemini request failed.", { status: geminiResponse.status });
    throw new Error("gemini_request_failed");
  }

  const responseBody = await geminiResponse.json();
  const responseText = readGeminiText(responseBody);
  if (!responseText) throw new Error("gemini_response_missing");

  let parsed;
  try {
    parsed = JSON.parse(responseText);
  } catch {
    throw new Error("gemini_response_invalid_json");
  }

  const recommendations = mergeValidatedRankings(parsed, candidates);
  if (recommendations === null) {
    throw new Error("gemini_response_invalid_shape");
  }

  return recommendations;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: responseHeaders,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse(
      { error: "Method not allowed. Use POST." },
      405,
      { Allow: "POST, OPTIONS" },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

  if (!supabaseUrl || !supabaseKey) {
    console.error("recommend-rooms is missing its Supabase public configuration.");
    return jsonResponse({ error: "Service configuration is unavailable." }, 500);
  }

  const bearerJwt = readBearerJwt(request.headers.get("Authorization"));
  if (!bearerJwt) {
    return jsonResponse(
      { error: "Authentication required." },
      401,
      { "WWW-Authenticate": "Bearer" },
    );
  }

  const authSupabase = createClient(supabaseUrl, supabaseKey);
  try {
    const { data, error } = await authSupabase.auth.getUser(bearerJwt);
    if (error || !data.user) {
      return jsonResponse(
        { error: "Invalid or expired authentication token." },
        401,
        { "WWW-Authenticate": "Bearer" },
      );
    }
  } catch {
    return jsonResponse(
      { error: "Invalid or expired authentication token." },
      401,
      { "WWW-Authenticate": "Bearer" },
    );
  }

  const supabase = createClient(supabaseUrl, supabaseKey, {
    global: { headers: { Authorization: `Bearer ${bearerJwt}` } },
  });

  let requestBody;
  try {
    requestBody = await request.json();
  } catch {
    return jsonResponse({ error: "Request body must be valid JSON." }, 400);
  }

  if (!isPlainObject(requestBody)) {
    return jsonResponse({ error: "Request body must be a JSON object." }, 400);
  }

  const validation = validateInput(requestBody);
  if ("error" in validation) {
    return jsonResponse({ error: validation.error }, 400);
  }

  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  const geminiModel = Deno.env.get("GEMINI_MODEL");

  if (!geminiApiKey || !geminiModel) {
    console.error("recommend-rooms is missing its Gemini configuration.");
    return jsonResponse({ error: "AI recommendation service is unavailable." }, 500);
  }

  const input = validation.data;

  try {
    const { data, error } = await supabase
      .rpc("search_available_rooms", {
        p_check_in_date: input.checkInDate,
        p_check_out_date: input.checkOutDate,
        p_guests: input.guests,
        p_branch_id: input.branchId,
        p_room_type_id: input.roomTypeId,
        p_min_price: input.minPrice,
        p_max_price: input.maxPrice,
      })
      .limit(15);

    if (error) {
      console.error("search_available_rooms failed.", { code: error.code });
      return jsonResponse({ error: "Unable to search available rooms." }, 502);
    }

    const candidates = Array.isArray(data) ? data.slice(0, 15) : [];
    if (candidates.length === 0) {
      return jsonResponse({
        candidateCount: 0,
        candidates: [],
        recommendations: [],
      });
    }

    let recommendations;
    try {
      recommendations = await rankCandidatesWithGemini(
        input.need,
        candidates,
        geminiApiKey,
        geminiModel,
      );
    } catch {
      console.error("Gemini ranking could not be completed.");
      return jsonResponse(
        { error: "AI recommendation service is unavailable." },
        502,
      );
    }

    return jsonResponse({
      candidateCount: candidates.length,
      candidates,
      recommendations,
    });
  } catch {
    console.error("recommend-rooms encountered an unexpected error.");
    return jsonResponse({ error: "Unable to process the request." }, 500);
  }
});
