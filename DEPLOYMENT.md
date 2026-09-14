# Deploying Project Board to the web (GitHub + Supabase)

A beginner-friendly walkthrough for taking `project-board.html` off your
C: drive and hosting it as a real website, with Supabase as the database.

## Read this first — an important gap

Right now, this app saves its data using a feature that only exists
**inside Claude.ai** (when the page is opened as a "Claude Artifact"). Once
you host the file yourself on GitHub Pages, that feature is gone — the
page will load and look the same, but nothing you type or change will be
saved anywhere. It'll disappear the moment you refresh the page.

To fix that, the app's code needs to be changed so that, instead of
talking to Claude's database, it talks to your Supabase database directly
(Supabase gives you a small JavaScript library and a web address for this).
That's a real code change to `project-board.html`, not just a hosting
setting — and it isn't covered in this guide, since you asked for the
hosting instructions on their own.

**What this guide gets you:** the site live on the internet, and a
Supabase project ready and waiting.
**What it doesn't get you yet:** the site actually saving data to that
Supabase project. For that, come back and ask to have the code wired up —
it's a separate, self-contained step you can do at any time after this.

If you'd rather skip all of this, the site already works today, for free,
simply by staying a Claude Artifact — no hosting or database setup needed.
This guide is for when you specifically want your own web address and your
own database outside of Claude.

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

8. Refresh the GitHub page — you should now see `project-board.html` and
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

6. Your `project-board.html` file will be reachable at:

   ```
   https://YOUR-USERNAME.github.io/project-board/project-board.html
   ```

   (Optional nice-to-have: rename `project-board.html` to `index.html`
   — either in File Explorer or by asking Claude to do it — so the site
   loads at the shorter address without the filename on the end. If you
   do this, remember to `git add`, commit, and `git push` the rename.)

That's it — the page is now genuinely on the world wide web, and anyone
with the link can open it. Remember the caveat from the top of this guide:
it will look right, but nothing typed into it will be saved yet.

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

   Keep this settings page bookmarked; you'll need to copy these two
   values into the app's code when it's time to connect it (that's the
   step described in "Read this first" above).

At this point your Supabase project exists and is empty — no tables yet.
Setting up the actual table (to hold projects, action items, etc.) and
wiring the app to read and write to it is exactly the code-change step
mentioned at the top: come back and ask for that whenever you're ready,
and hand over the Project URL and anon key from this step.

---

## Quick reference — what you have after this guide

| Thing | Where |
|---|---|
| Your code, versioned | `github.com/YOUR-USERNAME/project-board` |
| Your live website | `YOUR-USERNAME.github.io/project-board/project-board.html` |
| Your database (empty, unconnected) | Your Supabase project dashboard |

| Still to do | Why |
|---|---|
| Rewrite the app's save/load code to call Supabase instead of Claude's database | Otherwise nothing typed on the hosted site is saved anywhere |
| Create a table in Supabase for the board's data | The database has no structure yet |
| Decide who can read/write the data (Supabase's "Row Level Security") | By default a fresh Supabase table can be locked down completely — worth deciding on purpose, since this site would otherwise be open to the public internet |

## Making future changes

Once this is set up, to publish an update: commit the change locally
(as you already do), then run `git push`. GitHub Pages picks it up and
the live site updates within a minute or two, automatically.
