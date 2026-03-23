# Jogu Knows v1.0 — Release Guide (MoP Classic)

This guide covers publishing Jogu Knows as a MoP Classic addon (Interface 50400) across all major distribution platforms. All platforms are free.

---

## Prerequisites

Before starting, make sure these are done:

- [ ] All code changes committed to `main` branch
- [ ] `.pkgmeta` file exists in repo root (already created)
- [ ] `.github/workflows/release.yml` exists (already created)
- [ ] `Jogu.toc` has correct metadata (`## Interface: 50400`, `## Version: 1.0`)

---

## Step 1 — Create Accounts on Distribution Platforms

You need accounts on three platforms. Sign up if you haven't already:

1. **CurseForge**: https://www.curseforge.com (sign in via Overwolf/CurseForge account)
2. **Wago Addons**: https://addons.wago.io (sign in via Battle.net, GitHub, or Discord)
3. **WoWInterface**: https://www.wowinterface.com (create account)

---

## Step 2 — Create Your Addon Project on Each Platform

### CurseForge

1. Go to https://www.curseforge.com/project/create
2. Select **World of Warcraft > Addons**
3. Fill in:
   - **Name**: Jogu Knows
   - **Summary**: Predicts tomorrow's bonus crop for your Sunsong Ranch, tracks alt farming status and world boss lockouts
   - **Description**: Use the README content or write a CurseForge-specific description
   - **Game Version**: Select **Mists of Pandaria Classic** from the version dropdown
   - **Category**: Choose the most relevant (Farming/Gathering, or Info/Compilations)
4. Submit — your project will be queued for moderation review
5. Once approved, note your **Project ID** (visible in the URL or the "About This Project" sidebar)

### Wago Addons

1. Go to https://addons.wago.io and log in
2. Create a new addon project
3. Fill in name, description, and select MoP Classic compatibility
4. Once created, find your **X-Wago-ID** (8-character alphanumeric code shown beneath your addon name in the developer dashboard)

### WoWInterface

1. Go to https://www.wowinterface.com/downloads/filecpl.php
2. Choose **Upload New File**
3. Fill in addon details, select **Classic - General** category
4. Upload your addon zip manually for the initial release
5. Note your **addon ID** from the URL: `wowinterface.com/downloads/info{ID}-JoguKnows`

---

## Step 3 — Add Platform IDs to Your TOC File

Once you have IDs from all three platforms, add them to `Jogu.toc`:

```
## Interface: 50400
## Title: Jogu Knows
## Notes: Predicts tomorrow's bonus crop for your Sunsong Ranch, tracks alt farming status and world boss lockouts
## Author: Awesomnia
## Version: 1.0
## X-Curse-Project-ID: XXXXXX
## X-Wago-ID: XXXXXXXX
## X-WoWI-ID: XXXXX
## SavedVariables: JoguDB

Core.lua
```

Replace the X values with your actual IDs. Commit this change.

---

## Step 4 — Generate API Tokens

You need API tokens so GitHub Actions can upload releases automatically.

### CurseForge (CF_API_KEY)

1. Go to https://support.curseforge.com/support/solutions/articles/9000208346
2. Apply for a CurseForge API key
3. Fill in your contact info, project details, and intended API use (automated addon releases)
4. Wait for Overwolf to review and approve (they'll email you the token)

### Wago (WAGO_API_TOKEN)

1. Log in to https://addons.wago.io
2. Go to your developer dashboard / account settings
3. Generate an API token
4. Copy the token immediately (it won't be shown again)

### WoWInterface (WOW_INTERFACE_API_TOKEN)

1. Log in to WoWInterface
2. Go to your account settings
3. Generate an API key
4. Copy the token

### GitHub (GITHUB_OAUTH)

The built-in `GITHUB_TOKEN` secret (used in the workflow as `secrets.GITHUB_TOKEN`) is automatically provided by GitHub Actions — you don't need to create this manually. It handles creating the GitHub Release.

---

## Step 5 — Store Tokens as GitHub Secrets

1. Go to your repo: https://github.com/Awesomnian/Jogu
2. Navigate to **Settings → Secrets and variables → Actions**
3. Click **New repository secret** for each:

| Secret Name | Value |
|-------------|-------|
| `CF_API_KEY` | Your CurseForge API key |
| `WAGO_API_TOKEN` | Your Wago API token |
| `WOW_INTERFACE_API_TOKEN` | Your WoWInterface API key |

The `GITHUB_TOKEN` is automatic — don't add it manually.

---

## Step 6 — Tag and Push the Release

This is the step that triggers everything. Make sure all your changes are committed first.

```bash
# Make sure you're on main with everything committed
git status

# Create an annotated tag
git tag -a v1.0.0 -m "v1.0 - Jogu Knows initial release"

# Push the commit(s) and tag
git push origin main
git push origin v1.0.0
```

The `v1.0.0` tag push triggers the GitHub Actions workflow, which:

1. Checks out your repo
2. Reads `.pkgmeta` to know what to include/exclude
3. Packages the addon into a `Jogu-v1.0.0.zip`
4. Generates a changelog from git commits
5. Creates a GitHub Release with the zip attached
6. Uploads to CurseForge (if `CF_API_KEY` is set)
7. Uploads to Wago Addons (if `WAGO_API_TOKEN` is set)
8. Uploads to WoWInterface (if `WOW_INTERFACE_API_TOKEN` is set)

---

## Step 7 — Verify the Release

After the GitHub Action completes (1-2 minutes):

1. **GitHub**: Check https://github.com/Awesomnian/Jogu/releases — you should see v1.0.0 with the zip
2. **CurseForge**: Check your project page — the file will appear after moderation review (business hours, CET timezone, Sun-Thu)
3. **Wago**: Check your addon page — should appear relatively quickly
4. **WoWInterface**: Check your addon page

---

## Step 8 — Verify the Packaged Addon Works

1. Download the zip from GitHub Releases
2. Extract it into your WoW AddOns folder: `World of Warcraft\_classic_\Interface\AddOns\`
3. The extracted folder should be named `Jogu` (the `package-as` value from `.pkgmeta`)
4. Launch MoP Classic, check that `/jogu` works correctly
5. Verify the zip does NOT contain: README.md, LICENSE, .gitignore, OLD Versions, .github folder

---

## Platform-Specific Notes for MoP Classic

### CurseForge
- Moderation review hours: 8AM-3PM CET (Sun-Thu). Late submissions may be reviewed next business day.
- Select "Mists of Pandaria Classic" as the game version when creating/uploading.
- First submission takes longer due to new project review.

### Wago Addons
- Supports MoP Classic as a game version.
- The X-Wago-ID in your TOC allows the Wago client to track your addon automatically.

### WoWInterface
- MoP Classic addons go under "Classic - General" category.
- First upload must be done manually through the web UI before automated uploads work.

### BigWigs Packager
- MoP Classic game flavor is `mists`.
- The packager auto-detects `## Interface: 50400` as MoP Classic.
- The workflow already uses `BigWigsMods/packager@v2` which supports the `mists` flavor.

---

## Future Releases

For subsequent updates, the process is just:

```bash
# 1. Make your changes and commit them
git add Core.lua Jogu.toc
git commit -m "v1.1 - Added new feature"

# 2. Update ## Version in Jogu.toc to match

# 3. Tag and push
git tag -a v1.1.0 -m "v1.1 - Description of changes"
git push origin main
git push origin v1.1.0
```

The GitHub Action handles everything else automatically.

---

## Troubleshooting

**GitHub Action fails**: Check the Actions tab on your repo for error logs. Common issues are missing/invalid API tokens.

**CurseForge upload rejected**: Ensure `X-Curse-Project-ID` in TOC matches your actual project ID. Verify the game version is set correctly.

**Wago upload fails**: Verify `X-Wago-ID` is correct (8 characters, alphanumeric). Regenerate your API token if it's expired.

**Packaged zip is wrong**: Check `.pkgmeta` — make sure `package-as: Jogu` is correct and the `ignore` list includes everything that shouldn't ship.

**Tag didn't trigger workflow**: Make sure the tag starts with `v` (matching the `tags: - "v*"` pattern in `release.yml`).
