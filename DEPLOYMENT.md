# Deploying Project Board to the web (GitHub + Supabase)

A beginner-friendly walkthrough for taking `index.html` off your
C: drive and hosting it as a real website, with Supabase as the database.

## Status: the code is wired up

`index.html` now talks to Supabase directly (instead of Claude's Artifact
database), requires sign-in before showing the board (matching the access
decision in Part 4), and logs who changes each action item to an
Activity tab. **Seven things still need doing before it actually works
when you open the live site** — all one-time, no-code steps:

1. **Run `supabase-setup.sql`** — open it, copy its contents, paste into
   Supabase → **SQL Editor** → New query, and click **Run**. This creates
   the table the app saves to and the security rule that requires
   sign-in.
2. **Run `supabase-activity-log.sql`** the same way — a second, separate
   script that creates the table behind the Activity tab (who changed
   what, and when).
   - **Already ran this on a previous version of the site?** Also run
     `supabase-migration-restore-deleted.sql` once — it adds the column
     the Activity page's "Restore" button (for deleted action items)
     needs. Safe to run even if you're not sure; it does nothing if
     already applied.
3. **Run `supabase-team-updates.sql`** too — creates the table behind the
   Team Update page's 4-question daily check-in (one row per person per
   day; posting again the same day amends that day's entry).
   - **Already ran an earlier version of this script?** Also run
     `supabase-migration-team-updates-questions.sql` once (adds the four
     question columns) and, if you'd also already had that version
     running, `supabase-migration-team-updates-one-per-day.sql` once too
     (enforces one row per person per day — note it deletes older
     same-day duplicates for the same person, keeping only the latest;
     see the comments in that file before running it). Both are safe to
     run even if you're not sure whether they're needed.
4. **Run `supabase-project-forecasts.sql`** too — creates the tables behind
   the Forecasting page. Each project can have multiple named forecasting
   lines (e.g. "Product A", "Product B"), and each line has its own
   locations and price per month.
   - **Already ran an earlier version of this script** (from before a
     project could have more than one line)? Run
     `supabase-migration-forecast-lines.sql` once instead — it moves your
     existing per-project numbers onto an automatically-created "Line 1"
     for each project, then updates the table structure to key off lines
     instead of projects. Safe to run even if you're not sure; it does
     nothing if already applied. Read the comments at the top of that file
     before running it — it changes the `project_forecasts` table's
     primary key and drops its old `project_id` column (your data is kept,
     just moved onto "Line 1").
   - **Already had lines but no per-line checkbox to include/exclude a
     line from the chart?** Run `supabase-migration-forecast-line-chart-toggle.sql`
     once — it adds that column, defaulting every existing line to
     included (matching how they behaved before the toggle existed).
5. **Run `supabase-goals.sql`** too — creates the tables behind the Goals
   page. Every project can have up to 3 goals, all set for one shared
   "date for next goals" (the same date applies to every project, editable
   at the top of the page).
6. **Run `supabase-leave.sql`** too — creates the table behind the Leave
   page (one row per person: BOP — Balance at start Of Period — and
   PaySpace Entitlement, both entered manually (Entitlement defaults to
   25), plus their PaySpace Employee Number mapping. The page computes
   EOP as BOP + PaySpace Entitlement − PaySpace Applications for the
   current cycle).
   - **Already ran an earlier version of this script** (from before the
     PaySpace Employee Number mapping existed)? Run
     `supabase-migration-leave-payspace-number.sql` once — it just adds
     that column. Safe to run even if you're not sure; it does nothing if
     already applied.
   - **Already ran an earlier version with entitlement/applications/
     adjustments columns instead of BOP?** Run
     `supabase-migration-leave-bop.sql` once — it adds the `bop` column
     without touching your old data (that old data just stops being
     read/written by the app).
   - **Already ran an earlier version without the editable PaySpace
     Entitlement field** (from when EOP used a flat 25 for everyone)?
     Run `supabase-migration-leave-payspace-entitlement.sql` once — it
     adds the `payspace_entitlement` column, defaulting every existing
     row to 25 so nothing changes for anyone until you edit it.
7. **Create at least one user account for yourself** — see Part 4 below
   ("What's left is entirely on the Supabase side"). Without an account,
   the sign-in screen has no one to let in.
8. **Deploy the `manage-users` Edge Function** — see Part 5 below. This
   powers the Settings page's "User management" section (invite/remove
   people, and who can see Settings/Activity/SIM Cards/Team Update/
   Forecasting/Goals/Leave); everything else works without it.

Once the first seven are done, push the code (see Part 1) and the live
site will save, sync, and log activity for real, for anyone you've
created an account for. Part 5 (Edge Function) is separate and only
needed for in-app invite/remove/page-access.

---

## Part 0 — Things to install first

You only do this once, ever, on this computer.

1. **Git for Windows** — lets you send your project to GitHub.
   Download from [git-scm.com/download/win](https://git-scm.com/download/win)
   and run the installer, accepting all the defaults (just keep clicking
   "Next").
2. **A GitHub account** — free. Sign up at
   [github.com/signup](https://github.com/signup) if you don't have one.
3. **A Supabase account** — free. Sign up at
   [supabase.com](https://supabase.com) (the "Start your project" button),
   easiest is to sign up with your GitHub account so you only manage one
   login.

You do **not** need to install anything else — no Node.js, no command-line
tools beyond Git itself.

---

## Part 1 — Put the project on GitHub

GitHub is where your code will live online. Think of it as a folder on the
internet that also remembers every past version.

1. Go to [github.com](https://github.com) and log in.
2. Click the **+** icon (top right) → **New repository**.
3. Name it something like `project-board`.
4. Leave it set to **Public** (so GitHub Pages can serve it for free).
5. **Do not** tick "Add a README" — this project already has files in it.
6. Click **Create repository**. GitHub will show you a page with some
   commands — you don't need to run those, follow the steps below instead.
7. On your computer, open **PowerShell** (search for it in the Start
   menu) and run these commands one at a time, replacing
   `YOUR-USERNAME` with your actual GitHub username (you'll see the exact
   URL on the GitHub page from step 6 — you can copy it from there
   instead of typing it):

   ```powershell
   cd "C:\Users\Wim\Documents\Actions tool"
   git remote add origin https://github.com/YOUR-USERNAME/project-board.git
   git branch -M main
   git push -u origin main
   ```

   The first time you push, a window may pop up asking you to log in to
   GitHub — sign in there and it'll remember you next time.

8. Refresh the GitHub page — you should now see `index.html` and
   your other files listed there.

From now on, whenever you (or Claude, on your behalf) make changes and
commit them, you can send the update to GitHub with just:

```powershell
git push
```

---

## Part 2 — Turn the repository into a live website (GitHub Pages)

1. On your repository's GitHub page, click **Settings** (top menu).
2. In the left sidebar, click **Pages**.
3. Under "Build and deployment" → "Source", choose **Deploy from a
   branch**.
4. Under "Branch", choose **main** and folder **/ (root)**, then click
   **Save**.
5. Wait about a minute, then refresh the page — GitHub will show a green
   box with your site's address, something like:

   ```
   https://YOUR-USERNAME.github.io/project-board/
   ```

6. Since the app's file is named `index.html`, that address is all you
   need — GitHub Pages serves it automatically at the root URL, no
   filename on the end required.

That's it — the page is now genuinely on the world wide web, and anyone
with the link can open it. Remember the "Status" note at the top of this
guide: the sign-in screen will show, but nobody can actually get in or
save anything until you've run `supabase-setup.sql` and created a user
account (Part 4).

---

## Part 3 — Create your Supabase project

This sets up the database that will eventually hold your board's data.

1. Log in at [supabase.com](https://supabase.com) and click
   **New project**.
2. Pick an organization (Supabase creates a personal one for you
   automatically) and give the project a name, e.g. `project-board`.
3. Set a **database password** — click "Generate a password" and then
   **copy it somewhere safe** (a notes app, a password manager). You'll
   rarely need it directly, but it's hard to recover later.
4. Pick a region close to you or your team, then click **Create new
   project**. This takes a minute or two to provision — Supabase shows a
   progress screen.
5. Once it's ready, go to **Project Settings** (gear icon, bottom of the
   left sidebar) → **API**. You'll see two values you'll need later:
   - **Project URL** — looks like `https://abcdefgh.supabase.co`
   - **anon public** key — a long string of letters and numbers

   Keep this settings page bookmarked — these are the same Project URL
   and key already built into `index.html`, so you shouldn't need them
   again unless you create a different Supabase project later.

At this point your Supabase project exists but has no tables yet — that's
what `supabase-setup.sql` is for (see "Status" at the top of this guide).

---

## Part 4 — Managing who can access the site and its data

**Decision made: sign-in required, no public sign-up.** Anyone opening
the site will need an account you've created for them ahead of time —
there's no self-service signup, and nobody gets in without one. The rest
of this section explains how that works and what to do about it now.

### There are two separate doors, not one

1. **Can someone load the web page at all?**
   GitHub Pages sites are public by default — anyone with the link can
   open `index.html`, the same way anyone can open any other
   public website. There's no username/password on the page itself
   unless the app is built to have one. (Making the *page* itself private
   at the hosting level needs a paid GitHub plan; for a small team, it's
   both cheaper and more useful to add a proper sign-in screen inside the
   app instead — see below.)

2. **Can someone read or change the data?**
   This is controlled entirely by Supabase, through a feature called
   **Row Level Security (RLS)**. Every Supabase table starts with RLS
   fully locked — by default, nobody can read or write anything, not
   even your own app, until you write a rule that says otherwise. This
   is good: it means a forgotten step fails safe (no access) rather than
   failing open (public access).

   A subtlety worth understanding: the "anon" API key your app uses
   (from Part 3) is not a secret — it's embedded in the page's own code,
   so literally anyone who views the page's source can see it. It
   identifies your *project*, not a *person*. The actual protection comes
   from your RLS rules and from requiring people to sign in — never from
   hiding that key.

### How this setup works

Since this board is shared team information (not something where each
person should only see their own slice), it pairs with the simplest model
that's still genuinely secure:

- **Sign-in required, no public sign-up.** Anyone opening the site sees a
  login screen. You (Wim) add each teammate's email address in Supabase
  ahead of time; nobody can create their own account.
- **Once signed in, everyone can see and edit everything** — same as
  today's Claude Artifact, where anyone with access to it can edit
  freely. No per-person permission levels, keeping it simple.
- **Signed out = nothing.** No board data is visible to anyone who
  hasn't been explicitly added.

**The code side is done** — `index.html` has a login screen (email +
password, using Supabase's own sign-in function), and `supabase-setup.sql`
creates the Row Level Security rule that only allows signed-in users to
read or write the board's data.

**What's left is entirely on the Supabase side, no code needed:**

1. Run `supabase-setup.sql` if you haven't already (see "Status" at the
   top of this guide).
2. In your Supabase project, go to **Authentication** (left sidebar).
3. Under **Providers**, confirm **Email** is enabled (it is by default).
4. **Point invite links at your real site, not `localhost:3000`.** New
   Supabase projects default to a placeholder redirect address that
   doesn't exist anywhere. Go to **Authentication → URL Configuration**,
   set **Site URL** to your live site's address (e.g.
   `https://YOUR-USERNAME.github.io/project-board/`), and add that same
   address under **Redirect URLs** too. Skip this and any invite email
   will land people on a "can't connect" page instead of the board.
5. Go to **Authentication → Users** and click **Add user** → **Create new
   user** for yourself and each teammate who should have access. Use
   "Auto Confirm User" so they don't need to click an email link the
   first time (you can also invite by email instead — or, once Part 5's
   Edge Function is deployed, invite people from inside the app's
   Settings page).
6. Set a temporary password for each person, and share it with them
   privately (not over email in plain text) — Supabase's dashboard lets
   you reset anyone's password later if they need to change it.
   (People invited by email instead get no password at all until they
   click **Change password** inside the app after their first sign-in.)

### If you want to change this later

Other models are possible — e.g., read-only access for some people, or
each person only editing their own items — but they add real complexity
(more rules, more testing, more edge cases) for a tool where the whole
point is everyone seeing the same shared board. The chosen model above is
the simplest option that's still properly access-controlled; revisit it
only if a specific need for something more restrictive comes up.

---

## Part 5 — Deploy the user-management Edge Function

The Settings page has an admin-only "User management" section (invite
people by email, remove accounts, and tick which of the Settings,
Activity, SIM Cards, Team Update, Forecasting, Goals, and Leave pages
each person can see). It only works for the account whose email matches
`ADMIN_EMAIL` in `supabase-edge-function/manage-users.ts` (currently
`wim@hawktivity.com`) — everyone else won't even see that section.
By default, nobody but the admin can see any of those seven pages —
that's controlled by the checkboxes in this section, one tick per
person per page.

**Why this needs a separate step:** inviting and deleting users requires
Supabase's admin API, which only works with the `service_role` key — an
all-powerful secret that must never be embedded in the app's client-side
code (unlike the public key already in `index.html`, this one bypasses
every security rule). An Edge Function is a small piece of code that
Supabase runs on its own servers, where that secret can stay hidden while
still letting the app call it safely over the internet.

1. In your Supabase project, go to **Edge Functions** (left sidebar).
2. Click **Deploy a new function** (or **Create function** — wording
   varies slightly by Supabase version).
3. Name it exactly `manage-users` (the app calls it by this name).
4. Open `supabase-edge-function/manage-users.ts` from this project folder,
   select all, copy it, and paste it into the function's code editor,
   replacing whatever template code is there.
5. Click **Deploy**. Supabase automatically provides the function with
   the project's URL and service_role key — you don't need to enter or
   copy those anywhere yourself.
6. Test it: sign in to your live site as `wim@hawktivity.com`, open
   **Settings**, and you should see "User management" at the bottom with
   a list of current users instead of an error.

**Already had this function deployed before per-page access existed
(or before Team Update, Forecasting, Goals, or Leave were added)?**
Re-copy `supabase-edge-function/manage-users.ts` into it and redeploy
(steps 4-5 above) to pick up the checkboxes. One consequence worth
knowing: the moment this redeploys, everyone except the admin loses
access to Settings, Activity, SIM Cards, Team Update, Forecasting,
Goals, and Leave until you re-tick the pages they should keep seeing —
nothing else about their account changes.

Before inviting anyone from this section, make sure Part 4 step 4 (Site
URL / Redirect URLs pointing at your real site, not `localhost:3000`) is
done — otherwise invite links will send people to a page that doesn't
exist.

If your Supabase project doesn't show a code editor for this (some
older or restricted plans don't), the alternative is installing the
[Supabase CLI](https://supabase.com/docs/guides/cli) and running
`supabase functions deploy manage-users` from this project folder — ask
for help with this if the dashboard option isn't available to you.

**If the admin account ever needs to change:** edit the `ADMIN_EMAIL`
line near the top of `supabase-edge-function/manage-users.ts`, then
repeat steps 4-5 above to redeploy with the new value.

---

## Part 6 — Deploy the SIM Cards Edge Function

The rail has an admin-only **SIM Cards** tab (only `wim@hawktivity.com`
sees it) showing each SIM's data balance, average daily usage,
yesterday's usage, expected data-runout date, and last recharge date —
pulled live from your [SIMcontrol](https://app.simcontrol.co.za)
account.

**Why this needs a separate step:** reading this data requires your
SIMcontrol API key, which — like the service_role key in Part 5 — must
never be embedded in the app's client-side code, since `index.html` is
public. This Edge Function holds that key on Supabase's servers instead,
where the browser never sees it.

1. Run `supabase-sim-daily-balances.sql` in Supabase's SQL Editor — this
   creates the table the function writes each SIM's balance to every day
   it runs, which is how it detects recharges (a day where the balance is
   higher than the day before). History only starts once this table
   exists; see the comments at the top of that file for backfilling
   1 September 2026 onward by hand.
2. In your Supabase project, go to **Edge Functions** (left sidebar).
3. Click **Deploy a new function** and name it exactly `sim-cards` (the
   app calls it by this name).
4. Open `supabase-edge-function/sim-cards.ts` from this project folder,
   select all, copy it, and paste it into the function's code editor,
   replacing whatever template code is there. Click **Deploy**.
5. Open the `sim-cards` function's **Secrets** settings and add two:
   - `SIMCONTROL_API_KEY` = your SIMcontrol API key (find it in
     SIMcontrol under your account/API settings — it's the `X-API-Key`
     value, a string starting with `sc_`).
   - `CRON_SECRET` = any random string you make up (a password
     generator's output is fine) — this is what lets the daily scheduled
     run in step 7 below prove it's allowed to call this function without
     a signed-in user. Keep the value handy, you'll need it again in a
     moment.

   If your Supabase plan doesn't expose a per-function secrets UI, set
   these project-wide instead: **Edge Functions → Manage secrets**, or
   via the [Supabase CLI](https://supabase.com/docs/guides/cli):
   `supabase secrets set SIMCONTROL_API_KEY=sc_... CRON_SECRET=...`
6. Test it: sign in to your live site as `wim@hawktivity.com` — you
   should see a **SIM Cards** tab in the rail with a table of SIMs
   instead of an error.
7. **Make the daily balance recording happen even when nobody opens the
   page:** open `supabase-sim-cards-daily-cron.sql` from this project
   folder, replace its two placeholders (the `CRON_SECRET` value from
   step 5, and your project ref from Project Settings → API → Project
   URL) with the real values, then run it in Supabase's SQL Editor. This
   schedules a call to the function once a day (02:00 UTC by default —
   edit the two numbers in the file to change that) so recharge detection
   keeps working even through a quiet week. See the comments in that file
   for how to check it's actually firing, or stop it.

**Never paste the SIMcontrol API key, or the filled-in
`supabase-sim-cards-daily-cron.sql` with your real `CRON_SECRET` in it,
into `index.html`, a commit, or anywhere else that ends up in the GitHub
repo** — both belong only in Supabase's own dashboard / SQL Editor, since
that repo (and the live site's page source) is public.

**If the admin account ever needs to change:** edit the `ADMIN_EMAIL`
line near the top of `supabase-edge-function/sim-cards.ts`, then repeat
step 3 above to redeploy with the new value.

---

## Part 7 — Deploy the PaySpace Edge Function

The Leave page can show each person's approved PaySpace Annual leave
applications for the current cycle (read-only, used in the EOP
calculation) once their PaySpace Employee Number is set and you click
**Sync from PaySpace**. This never writes anything back to PaySpace,
and never overwrites your manually-entered BOP or PaySpace Entitlement
fields.

**Why this needs an Edge Function:** every table in this app's database
is readable by any signed-in user (page-access checkboxes only hide
tabs in the browser — they're not a real security boundary). A PaySpace
`client_secret` is a real credential that can pull your company's
payroll/HR data, so it needs the same treatment as the SIMcontrol key
and the service_role key above: a Supabase Edge Function secret, which
only server-side function code can ever read — never a table, and
never `index.html`.

1. In your Supabase project, go to **Edge Functions** (left sidebar).
2. Click **Deploy a new function** and name it exactly `payspace` (the
   app calls it by this name).
3. Open `supabase-edge-function/payspace.ts` from this project folder,
   select all, copy it, and paste it into the function's code editor,
   replacing whatever template code is there. Click **Deploy**.
4. Open the `payspace` function's **Secrets** settings (or **Edge
   Functions → Manage secrets** if your plan doesn't expose a
   per-function UI, or via the CLI: `supabase secrets set`) and add:
   - `PAYSPACE_CLIENT_ID` = your PaySpace API client ID
   - `PAYSPACE_CLIENT_SECRET` = your PaySpace API client secret
   (Find both in PaySpace under **Config → Basic Settings → General
   Company → Integrations → API Credentials**. The secret is shown only
   once, right after you save — copy it immediately.)
   - `PAYSPACE_COMPANY_ID` — only needed if your PaySpace account has
     more than one company; otherwise the function picks the first one
     automatically from the token response.
5. On the Leave page, click each person's "+ Add" under **PaySpace #**
   and enter their PaySpace Employee Number (find these in PaySpace's
   employee list) — this is a one-time mapping stored per person.
6. Test it: click **Sync from PaySpace**. You should see a PaySpace
   Applications figure (click it to see the individual dates) for
   anyone with a PaySpace # set — anyone without a match there, or
   without a PaySpace # set, just shows "—" and their EOP can't be
   computed until they do.

**Never paste either credential into `index.html`, a commit, or this
chat** — Supabase's secrets UI is the only place they should ever be
typed.

---

## Quick reference — what you have after this guide

| Thing | Where |
|---|---|
| Your code, versioned | `github.com/YOUR-USERNAME/project-board` |
| Your live website | `YOUR-USERNAME.github.io/project-board/` |
| Your database, wired up and code-complete | Your Supabase project dashboard |
| Teammate accounts (add these in Part 4) | Supabase → Authentication → Users |

| Still to do | Why |
|---|---|
| Run `supabase-setup.sql` in Supabase's SQL Editor | Creates the table the app saves to and its sign-in-required security rule — nothing saves until this runs |
| Run `supabase-activity-log.sql` too | Creates the table behind the Activity tab — without it, Activity shows an error instead of a log |
| Run `supabase-team-updates.sql` too | Creates the table behind the Team Update page (one row per person per day) |
| Run `supabase-project-forecasts.sql` too | Creates the tables behind the Forecasting page (each project can have multiple named lines, each with its own locations & price per month) |
| Already had an earlier one-line-per-project version? Run `supabase-migration-forecast-lines.sql` once | Moves existing forecasts onto an auto-created "Line 1" per project and updates the table structure — read its comments first, it changes a primary key |
| Already had lines but no chart include/exclude checkbox? Run `supabase-migration-forecast-line-chart-toggle.sql` once | Adds that column, defaulting every existing line to included |
| Run `supabase-goals.sql` too | Creates the tables behind the Goals page (up to 3 goals per project, all for one shared target date) |
| Run `supabase-leave.sql` too | Creates the table behind the Leave page (BOP + PaySpace Entitlement (default 25, both editable) + PaySpace # per person; EOP = BOP + PaySpace Entitlement − PaySpace Applications) |
| Already had an earlier version without the PaySpace # column? Run `supabase-migration-leave-payspace-number.sql` once | Adds that column |
| Already had an earlier version with entitlement/applications/adjustments instead of BOP? Run `supabase-migration-leave-bop.sql` once | Adds the `bop` column — old data is kept, just no longer read/written |
| Already had BOP but a flat 25 instead of editable PaySpace Entitlement? Run `supabase-migration-leave-payspace-entitlement.sql` once | Adds the `payspace_entitlement` column, defaulting every row to 25 |
| Create at least one user account (Part 4) | The sign-in screen has no one to let in until an account exists |
| Deploy `manage-users` (Part 5) | Powers Settings' invite/remove-user controls — everything else works without this one |
| Run `supabase-sim-daily-balances.sql` too | Creates the table the SIM Cards function writes daily balances to, for recharge detection (Part 6) — backfill 1 September 2026 onward by hand |
| Deploy `sim-cards` and set `SIMCONTROL_API_KEY` + `CRON_SECRET` (Part 6) | Powers the admin-only SIM Cards tab — everything else works without this one |
| Run `supabase-sim-cards-daily-cron.sql` too (with its placeholders filled in) | Schedules a daily call to `sim-cards` so balance history keeps recording even on days nobody opens the page |
| Deploy `payspace` and set `PAYSPACE_CLIENT_ID` / `PAYSPACE_CLIENT_SECRET` (Part 7, optional) | Powers the Leave page's "Sync from PaySpace" read-only comparison columns — everything else on that page works without this one |

## Making future changes

Once this is set up, to publish an update: commit the change locally
(as you already do), then run `git push`. GitHub Pages picks it up and
the live site updates within a minute or two, automatically.
