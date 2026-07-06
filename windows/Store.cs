using System.Reflection;
using System.Text.Json;
using Microsoft.Win32;

namespace ConsoClaude;

// Persistance locale — équivalent Windows du UserDefaults + bundle du mac.
// Tout vit dans %APPDATA%\ConsoClaude\ ; rien de sensible (aucune réponse API).
public static class Store
{
    public static readonly string Dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ConsoClaude");

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = false };

    static Store() => Directory.CreateDirectory(Dir);

    private static string Path_(string name) => System.IO.Path.Combine(Dir, name);

    private static T Read<T>(string name, T fallback)
    {
        try
        {
            var p = Path_(name);
            if (!File.Exists(p)) return fallback;
            return JsonSerializer.Deserialize<T>(File.ReadAllText(p)) ?? fallback;
        }
        catch { return fallback; }
    }

    private static void Write<T>(string name, T value)
    {
        try { File.WriteAllText(Path_(name), JsonSerializer.Serialize(value, Json)); }
        catch { /* best-effort : un cache non écrit n'est pas fatal */ }
    }

    // MARK: Historique (sparkline + prédiction)

    public static List<HistoryPoint> LoadHistory() => Read("history.json", new List<HistoryPoint>());
    public static void SaveHistory(List<HistoryPoint> h) => Write("history.json", h);

    // MARK: Cache d'état (l'app relancée affiche direct les dernières données)

    public sealed class CachedLimit
    {
        public string Kind { get; set; } = "?";
        public string Label { get; set; } = "?";
        public int Percent { get; set; }
        public string Severity { get; set; } = "normal";
        public string ResetsAt { get; set; } = "";
    }

    public sealed class CachedState
    {
        public List<CachedLimit> Limits { get; set; } = new();
        public DateTime? FetchedAt { get; set; }
    }

    public static CachedState LoadCache() => Read("cache.json", new CachedState());
    public static void SaveCache(CachedState c) => Write("cache.json", c);

    // MARK: Anti-répétition des phrases

    public static List<string> RecentPhrases() => Read("recent-phrases.json", new List<string>());
    public static void SetRecentPhrases(List<string> v) => Write("recent-phrases.json", v);

    // MARK: Pool de phrases — override utilisateur (%APPDATA%) sinon copie embarquée.

    public static Dictionary<string, List<string>> Phrases()
    {
        var result = new Dictionary<string, List<string>>();
        // 1) Ressource embarquée (fallback garanti).
        MergePhrases(result, ReadEmbedded("phrases.json"));
        // 2) Override utilisateur (a le dernier mot en s'ajoutant au pool).
        try
        {
            var user = Path_("phrases.json");
            if (File.Exists(user)) MergePhrases(result, File.ReadAllText(user));
        }
        catch { }
        return result;
    }

    private static void MergePhrases(Dictionary<string, List<string>> into, string? jsonText)
    {
        if (string.IsNullOrEmpty(jsonText)) return;
        try
        {
            using var doc = JsonDocument.Parse(jsonText);
            foreach (var prop in doc.RootElement.EnumerateObject())
            {
                if (prop.Value.ValueKind != JsonValueKind.Array) continue; // ignore "_note" & co
                var list = into.TryGetValue(prop.Name, out var existing) ? existing : (into[prop.Name] = new());
                foreach (var el in prop.Value.EnumerateArray())
                    if (el.ValueKind == JsonValueKind.String) list.Add(el.GetString()!);
            }
        }
        catch { }
    }

    private static string? ReadEmbedded(string name)
    {
        var asm = Assembly.GetExecutingAssembly();
        var res = asm.GetManifestResourceNames().FirstOrDefault(n => n.EndsWith(name, StringComparison.OrdinalIgnoreCase));
        if (res is null) return null;
        using var s = asm.GetManifestResourceStream(res);
        if (s is null) return null;
        using var r = new StreamReader(s);
        return r.ReadToEnd();
    }

    public static string ReadEmbeddedText(string name) => ReadEmbedded(name) ?? "";

    // MARK: Démarrage au login (registre HKCU\...\Run — équivalent SMAppService).

    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunName = "ConsoClaude";

    public static bool LaunchAtLogin
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue(RunName) is string;
        }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (k is null) return;
            if (value)
            {
                var exe = Environment.ProcessPath ?? Assembly.GetExecutingAssembly().Location;
                k.SetValue(RunName, $"\"{exe}\"");
            }
            else k.DeleteValue(RunName, throwOnMissingValue: false);
        }
    }
}
