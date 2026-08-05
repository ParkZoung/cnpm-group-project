const IDENTIFIER = /^[a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)?$/;
const SELECT_EXPRESSION = /^[a-zA-Z0-9_.*(),!:\s]+$/;

export function validateQuery(body) {
  if (!body || typeof body !== "object") return "Invalid query body.";
  if (!['select', 'insert', 'update', 'delete'].includes(body.operation)) {
    return "Unsupported query operation.";
  }
  if (typeof body.columns !== "string" || !SELECT_EXPRESSION.test(body.columns)) {
    return "Invalid select expression.";
  }
  if (!Array.isArray(body.filters) || !Array.isArray(body.orders)) {
    return "Invalid query shape.";
  }
  if (body.filters.some((filter) =>
    !["eq", "neq", "gte", "lt", "in"].includes(filter.operator) ||
    typeof filter.column !== "string" || !IDENTIFIER.test(filter.column) ||
    (filter.operator === "in" && !Array.isArray(filter.value)))) {
    return "Invalid filter.";
  }
  if (body.orders.some((order) =>
    typeof order.column !== "string" || !IDENTIFIER.test(order.column) ||
    typeof order.ascending !== "boolean")) {
    return "Invalid ordering.";
  }
  if (body.limit !== undefined &&
      (!Number.isSafeInteger(body.limit) || body.limit < 1 || body.limit > 1000)) {
    return "Invalid limit.";
  }
  return null;
}
