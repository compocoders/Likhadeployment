# ─── Local Dev DB Setup Script ────────────────────────────────────────────────
# Creates the lp_dev database on your local PostgreSQL 18 and runs Prisma
# migrations. Run this once after cloning or switching from Neon.
#
# Usage: .\setup-local-db.ps1
#   OR:  .\setup-local-db.ps1 -PgPassword "yourpassword"
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$PgPassword = "yashu5368",
    [string]$PgUser     = "postgres",
    [string]$PgHost     = "127.0.0.1",
    [string]$PgPort     = "5432",
    [string]$DbName     = "lp_dev"
)

$pgBin = "C:\Program Files\PostgreSQL\18\bin"
$psql  = "$pgBin\psql.exe"
$envFile = "$PSScriptRoot\lp_be\.env"

# ── 1. Ask for password if not provided ───────────────────────────────────────
if (-not $PgPassword) {
    $secPw = Read-Host -AsSecureString "Enter password for local postgres user '$PgUser'"
    $PgPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPw)
    )
}

$env:PGPASSWORD = $PgPassword

# ── 2. Test connection ─────────────────────────────────────────────────────────
Write-Host "`n🔌 Testing connection to PostgreSQL 18..." -ForegroundColor Cyan
$test = & $psql -U $PgUser -h $PgHost -p $PgPort -c "SELECT version();" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Could not connect: $test" -ForegroundColor Red
    Write-Host "   Check your password and that the postgresql-x64-18 service is running." -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ Connected!" -ForegroundColor Green

# ── 3. Create database (skip if already exists) ────────────────────────────────
Write-Host "`n📦 Creating database '$DbName'..." -ForegroundColor Cyan
$exists = & $psql -U $PgUser -h $PgHost -p $PgPort -tAc "SELECT 1 FROM pg_database WHERE datname='$DbName';" 2>&1
if ($exists.Trim() -eq "1") {
    Write-Host "   Database '$DbName' already exists — skipping create." -ForegroundColor Yellow
} else {
    & $psql -U $PgUser -h $PgHost -p $PgPort -c "CREATE DATABASE $DbName;" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Database '$DbName' created!" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to create database." -ForegroundColor Red
        exit 1
    }
}

# ── 4. Update .env with real DATABASE_URL ─────────────────────────────────────
Write-Host "`n📝 Updating lp_be\.env with local DATABASE_URL..." -ForegroundColor Cyan
$newUrl = "postgresql://${PgUser}:${PgPassword}@${PgHost}:${PgPort}/${DbName}"
$envContent = Get-Content $envFile -Raw
# Replace any existing DATABASE_URL line value
$envContent = $envContent -replace 'DATABASE_URL=.*', "DATABASE_URL=`"$newUrl`""
Set-Content $envFile $envContent -NoNewline
Write-Host "✅ .env updated!" -ForegroundColor Green

# ── 5. Run Prisma migrations ───────────────────────────────────────────────────
Write-Host "`n🗃️  Running Prisma migrations..." -ForegroundColor Cyan
Push-Location "$PSScriptRoot\lp_be"
$migrateResult = npx prisma migrate deploy --config prisma.config.ts 2>&1
Write-Host $migrateResult
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Migrations applied!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Migration had issues — check output above." -ForegroundColor Yellow
}

# ── 6. Generate Prisma client ─────────────────────────────────────────────────
Write-Host "`n⚙️  Generating Prisma client..." -ForegroundColor Cyan
npx prisma generate --config prisma.config.ts 2>&1
Pop-Location

# ── 7. Done ───────────────────────────────────────────────────────────────────
Write-Host "`n🎉 Done! Your local dev database is ready." -ForegroundColor Green
Write-Host "   DATABASE_URL → $newUrl" -ForegroundColor DarkGray
Write-Host "   Run 'npm run dev' in lp_be\ to start the backend.`n" -ForegroundColor DarkGray
