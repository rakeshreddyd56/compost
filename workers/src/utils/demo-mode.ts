/**
 * Helpers for demo-only overrides.
 *
 * These flags intentionally stay noisy in logs so a forced demo mode does not
 * quietly survive past the hackathon run-through.
 */

const warned = new Set<string>();

export function demoFlagEnabled(name: string): boolean {
  const enabled = String(process.env[name] ?? "").trim().toLowerCase() === "true";
  if (enabled && !warned.has(name)) {
    console.warn(
      `[demo] ${name}=true; demo override is enabled. ` +
      "Disable it after the demo by removing it from .env and running `ntn workers env push --yes`."
    );
    warned.add(name);
  }
  return enabled;
}
