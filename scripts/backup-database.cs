#:package Microsoft.Data.Sqlite@10.0.12
// Hot, consistent backup of the Umbraco SQLite database using SQLite's online backup API.
//
// The live database is opened read-only; the app can keep running. The copy is a single
// self-contained .db file (pages still in the -wal file are included). The copy is then checked
// with PRAGMA integrity_check and summarised. Nothing is ever written to the live database.
//
// Usage (from the repository root):
//   dotnet run scripts/backup-database.cs
//   dotnet run scripts/backup-database.cs -- --dest backups/before-upgrade
//   dotnet run scripts/backup-database.cs -- --verify-only backups/20261115-210000-hot/Umbraco.sqlite.db
//
// Exit codes: 0 = backup (or verification) succeeded, 1 = integrity check failed, 2 = error.
using Microsoft.Data.Sqlite;

const string DefaultSource = "src/FunkyFreshFarm.UmbracoLab/umbraco/Data/Umbraco.sqlite.db";

try
{
    string? source = DefaultSource;
    string? dest = null;
    string? verifyOnly = null;
    for (int i = 0; i < args.Length; i++)
    {
        switch (args[i])
        {
            case "--source": source = args[++i]; break;
            case "--dest": dest = args[++i]; break;
            case "--verify-only": verifyOnly = args[++i]; break;
            default: throw new ArgumentException($"Unknown argument '{args[i]}'.");
        }
    }

    string backupFile;
    if (verifyOnly is not null)
    {
        backupFile = Path.GetFullPath(verifyOnly);
        if (!File.Exists(backupFile)) throw new FileNotFoundException("Backup file not found.", backupFile);
    }
    else
    {
        var sourceFile = Path.GetFullPath(source);
        if (!File.Exists(sourceFile)) throw new FileNotFoundException("Live database not found.", sourceFile);

        var destDir = Path.GetFullPath(dest ?? Path.Combine("backups", DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-hot"));
        Directory.CreateDirectory(destDir);
        backupFile = Path.Combine(destDir, "Umbraco.sqlite.db");
        if (File.Exists(backupFile)) throw new IOException($"Refusing to overwrite existing backup {backupFile}.");

        using (var live = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = sourceFile, Mode = SqliteOpenMode.ReadOnly, Pooling = false }.ToString()))
        using (var copy = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = backupFile, Mode = SqliteOpenMode.ReadWriteCreate, Pooling = false }.ToString()))
        {
            live.Open();
            copy.Open();
            live.BackupDatabase(copy);
        }

        Console.WriteLine($"Source : {sourceFile} (opened read-only)");
        Console.WriteLine($"Backup : {backupFile} ({new FileInfo(backupFile).Length:N0} bytes)");
    }

    using var db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = backupFile, Mode = SqliteOpenMode.ReadOnly, Pooling = false }.ToString());
    db.Open();

    string Scalar(string sql)
    {
        using var cmd = db.CreateCommand();
        cmd.CommandText = sql;
        return cmd.ExecuteScalar()?.ToString() ?? "";
    }

    const string Document = "C66BA18E-EAF3-4CFF-8A22-41B16D66A972";
    const string Media = "B796F64C-1F99-4FFB-B886-4BF4BC011A9C";
    var integrity = Scalar("PRAGMA integrity_check");
    Console.WriteLine($"Integrity check : {integrity}");
    Console.WriteLine($"Tables          : {Scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table'")}");
    Console.WriteLine($"Documents       : {Scalar($"SELECT count(*) FROM umbracoNode WHERE upper(nodeObjectType) = '{Document}' AND trashed = 0")}" +
                      $" (published: {Scalar("SELECT count(*) FROM umbracoDocument WHERE published = 1")})");
    Console.WriteLine($"Media items     : {Scalar($"SELECT count(*) FROM umbracoNode WHERE upper(nodeObjectType) = '{Media}' AND trashed = 0")}");
    Console.WriteLine($"Users           : {Scalar("SELECT count(*) FROM umbracoUser")}");
    Console.WriteLine($"Migration state : {Scalar("SELECT value FROM umbracoKeyValue WHERE key = 'Umbraco.Core.Upgrader.State+Umbraco.Core'")}");

    return integrity == "ok" ? 0 : 1;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Error: {ex.Message}");
    return 2;
}
