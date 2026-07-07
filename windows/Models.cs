namespace ConsoClaude;

// Une limite d'usage renvoyée par l'API (session 5 h, hebdo tous modèles, hebdo par modèle).
public sealed record UsageLimit(
    string Kind,
    string Label,
    int Percent,          // % CONSOMMÉ (comme l'API) ; le RESTANT = 100 - Percent est calculé à l'affichage.
    DateTime? ResetsAt,
    string Severity,
    bool IsSession);

// État courant affiché par l'app.
public sealed class UsageState
{
    public List<UsageLimit> Limits { get; set; } = new();
    public string? Error { get; set; }
    public DateTime? FetchedAt { get; set; }
    public bool Stale { get; set; }

    public UsageLimit? Session => Limits.FirstOrDefault(l => l.IsSession);
}

// Point d'historique local (pour sparkline + prédiction burn-rate).
public readonly record struct HistoryPoint(double T, int V);
