namespace ConsoClaude;

// Encouragement à l'anglaise — pools par palier + variantes contextuelles
// (nuit, vendredi soir, limite hebdo). Rotation sans resservir les 4 derniers.
// Port fidèle de encouragement(remaining:context:) du mac.
public static class Encouragement
{
    private static readonly Random Rng = new();

    public static string For(int remaining, string context)
    {
        var now = DateTime.Now;
        int hour = now.Hour;
        bool isNight = hour >= 23 || hour < 6;
        bool isFridayEvening = now.DayOfWeek == DayOfWeek.Friday && hour >= 17;
        bool isWeekly = context.ToLowerInvariant().Contains("weekly");

        List<string> pool;
        if (remaining >= 50)
        {
            pool = new()
            {
                "Plenty of runway left.",
                "Keep thinking big.",
                "Halfway there — pace yourself.",
                "The best half is still ahead.",
                "Deep breath. Deep work.",
                "Good thinking takes time. You have it.",
                "Still plenty of room to be curious.",
                "Onwards, thoughtfully.",
            };
            if (isWeekly) pool.Add("A week is a marathon. Pace it.");
        }
        else if (remaining >= 25)
        {
            pool = new()
            {
                "Make these tokens count.",
                "Good ideas take tokens.",
                "Still room for one great idea.",
                "Choose your next question well.",
                "Quality over quantity, from here.",
                "Sharpen the prompt, spare the tokens.",
                "Now's the time for your best question.",
                "Less throughput, more thought.",
            };
            if (isWeekly) pool.Add("Spend the week's thinking wisely.");
        }
        else
        {
            pool = new()
            {
                "Maybe it's time to rest.",
                "Almost out — finish strong.",
                "Land this plane gracefully.",
                "One good prompt left. Make it sing.",
                "Save something for tomorrow.",
                "Great work knows when to stop.",
                "Ship it, then step away.",
            };
            if (isWeekly) pool.Add("The week's almost spent. Spend it well.");
        }

        if (isNight)
            pool.AddRange(new[]
            {
                "It's late. Great ideas keep till morning.",
                "The tokens will still be here tomorrow.",
                "Night shift? Make it a short one.",
                "Maybe it's time to rest.",
            });
        if (isFridayEvening)
            pool.AddRange(new[]
            {
                "It's Friday. The week forgives.",
                "Weekend mode approaching.",
            });

        // Extension par phrases.json (embarqué + override utilisateur).
        var disk = Store.Phrases();
        string tier = remaining >= 50 ? "50" : (remaining >= 25 ? "25" : "10");
        if (disk.TryGetValue(tier, out var t)) pool.AddRange(t);
        if (isWeekly && disk.TryGetValue("weekly", out var w)) pool.AddRange(w);
        if (isNight && disk.TryGetValue("night", out var n)) pool.AddRange(n);
        if (isFridayEvening && disk.TryGetValue("friday", out var f)) pool.AddRange(f);

        // Éviter de resservir les derniers messages.
        var recent = Store.RecentPhrases();
        var fresh = pool.Where(p => !recent.Contains(p)).ToList();
        var choose = fresh.Count > 0 ? fresh : pool;
        var phrase = choose[Rng.Next(choose.Count)];
        recent.Add(phrase);
        if (recent.Count > 4) recent.RemoveRange(0, recent.Count - 4);
        Store.SetRecentPhrases(recent);
        return phrase;
    }

    // Pool spécial « la session repart de zéro ».
    public static string ForReset()
    {
        var pool = new List<string>
        {
            "Fresh tokens. Clean slate.",
            "New session, new ideas.",
            "The counter is kind again.",
        };
        var disk = Store.Phrases();
        if (disk.TryGetValue("reset", out var r)) pool.AddRange(r);
        return pool[Rng.Next(pool.Count)];
    }
}
