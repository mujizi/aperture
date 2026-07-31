const sensitiveKey =
  /^(?:api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|password|passwd|secret|token)$/i;

export function redactSensitiveText(input: string) {
  return input
    .replace(/\bsk-or-v1-[A-Za-z0-9_-]+\b/g, "[REDACTED_OPENROUTER_KEY]")
    .replace(
      /\b(Bearer\s+)[A-Za-z0-9._~+/=-]{16,}\b/gi,
      "$1[REDACTED_TOKEN]"
    );
}

export function redactSensitiveValue(value: unknown): unknown {
  if (typeof value === "string") return redactSensitiveText(value);
  if (Array.isArray(value)) return value.map(redactSensitiveValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, child]) => [
        key,
        sensitiveKey.test(key)
          ? "[REDACTED_SENSITIVE_VALUE]"
          : redactSensitiveValue(child)
      ])
    );
  }
  return value;
}
