const { readdirSync } = require('node:fs');
const { join } = require('node:path');

const directory = join('backend', 'supabase', 'migrations');
const migrationPattern = /^(\d{14})_[a-z0-9_]+\.sql$/;
const versions = new Map();
const errors = [];

for (const file of readdirSync(directory).sort()) {
  const match = file.match(migrationPattern);
  if (!match) {
    errors.push(`Invalid migration filename: ${file}`);
    continue;
  }
  if (versions.has(match[1])) {
    errors.push(`Duplicate migration version ${match[1]}: ${versions.get(match[1])}, ${file}`);
  } else {
    versions.set(match[1], file);
  }
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`Validated ${versions.size} unique migration versions.`);
}
