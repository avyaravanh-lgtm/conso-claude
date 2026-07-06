using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace ConsoClaude;

// Résultat d'un fetch : soit des limites, soit une erreur, soit un rate-limit (backoff).
public sealed class FetchResult
{
    public List<UsageLimit>? Limits { get; init; }
    public string? Error { get; init; }
    public bool RateLimited { get; init; }
    public double BackoffSeconds { get; init; }

    public static FetchResult Ok(List<UsageLimit> l) => new() { Limits = l };
    public static FetchResult Err(string e) => new() { Error = e };
    public static FetchResult Throttled(double s) => new() { RateLimited = true, BackoffSeconds = s };
}

// Lit le token de Claude Code puis interroge api.anthropic.com/api/oauth/usage —
// le même endpoint que la page « Limites d'utilisation ». Chiffres officiels.
public sealed class UsageClient
{
    // Session éphémère par principe : aucune réponse (autorisée par token) mise en cache HTTP.
    private readonly HttpClient _http;

    public UsageClient()
    {
        _http = new HttpClient(new SocketsHttpHandler
        {
            AllowAutoRedirect = false,
            AutomaticDecompression = DecompressionMethods.All,
        })
        {
            Timeout = TimeSpan.FromSeconds(15),
        };
    }

    // Sur Windows, Claude Code stocke le token en FICHIER CLAIR (pas de trousseau) :
    //   %USERPROFILE%\.claude\.credentials.json   (override via CLAUDE_CONFIG_DIR)
    // → lecture plus simple qu'en mac.
    public static string? ReadToken()
    {
        try
        {
            var configDir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrWhiteSpace(configDir))
                configDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");

            var path = Path.Combine(configDir, ".credentials.json");
            if (!File.Exists(path)) return null;

            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (doc.RootElement.TryGetProperty("claudeAiOauth", out var oauth) &&
                oauth.TryGetProperty("accessToken", out var tok) &&
                tok.ValueKind == JsonValueKind.String)
                return tok.GetString();
        }
        catch { }
        return null;
    }

    public async Task<FetchResult> FetchAsync(CancellationToken ct = default)
    {
        var token = ReadToken();
        if (token is null)
            return FetchResult.Err("Token not found — open Claude Code, then refresh.");

        using var req = new HttpRequestMessage(HttpMethod.Get, "https://api.anthropic.com/api/oauth/usage");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        req.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");

        HttpResponseMessage resp;
        try { resp = await _http.SendAsync(req, ct).ConfigureAwait(false); }
        catch (Exception e) { return FetchResult.Err($"Network: {e.Message}"); }

        using (resp)
        {
            if (resp.StatusCode == HttpStatusCode.TooManyRequests)
            {
                // Rate-limité : backoff silencieux — le cache reste affiché avec juste le ⚠.
                var retryAfter = resp.Headers.RetryAfter?.Delta?.TotalSeconds
                    ?? (double.TryParse(resp.Headers.RetryAfter?.ToString(), out var r) ? r : 900);
                var pause = Math.Max(900, Math.Min(retryAfter, 3600));
                return FetchResult.Throttled(pause);
            }
            if (resp.StatusCode == HttpStatusCode.Unauthorized)
                return FetchResult.Err("Token expired — open Claude Code, then refresh.");
            if (!resp.IsSuccessStatusCode)
                return FetchResult.Err($"API: HTTP {(int)resp.StatusCode}");

            string body;
            try { body = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false); }
            catch (Exception e) { return FetchResult.Err($"Read: {e.Message}"); }

            try
            {
                using var doc = JsonDocument.Parse(body);
                if (!doc.RootElement.TryGetProperty("limits", out var raw) || raw.ValueKind != JsonValueKind.Array)
                    return FetchResult.Err("API: unexpected response.");

                var limits = new List<UsageLimit>();
                foreach (var l in raw.EnumerateArray())
                {
                    var kind = Str(l, "kind") ?? "?";
                    string label = kind switch
                    {
                        "session" => "5-hour session",
                        "weekly_all" => "Weekly — all models",
                        "weekly_scoped" =>
                            "Weekly — " + (l.TryGetProperty("scope", out var sc) &&
                                          sc.TryGetProperty("model", out var m) &&
                                          m.TryGetProperty("display_name", out var dn) &&
                                          dn.ValueKind == JsonValueKind.String
                                ? dn.GetString() : "model"),
                        _ => kind,
                    };
                    limits.Add(new UsageLimit(
                        Kind: kind,
                        Label: label,
                        Percent: Int(l, "percent"),
                        ResetsAt: ParseDate(Str(l, "resets_at")),
                        Severity: Str(l, "severity") ?? "normal",
                        IsSession: kind == "session"));
                }
                return FetchResult.Ok(limits);
            }
            catch (Exception e) { return FetchResult.Err($"Parsing: {e.Message}"); }
        }
    }

    private static string? Str(JsonElement e, string k)
        => e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static int Int(JsonElement e, string k)
        => e.TryGetProperty(k, out var v) && v.TryGetInt32(out var n) ? n : 0;

    public static DateTime? ParseDate(string? s)
    {
        if (string.IsNullOrEmpty(s)) return null;
        return DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dto)
            ? dto.LocalDateTime : null;
    }
}
