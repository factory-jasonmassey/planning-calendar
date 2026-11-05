# Planning Calendar

A single-file planning calendar for things like new hire start dates, team travel, and customer engagements.

- Multiple calendars you can switch between
- Month, 3-month, 6-month, and year views
- Click, drag, or Shift-click to select and label a day or a range of days
- Headcount roster mode: a running list of people by start date, with counts for today and each month end
- Roster export and import as JSON (import merges: matching people are updated, new people are added, nobody is removed)
- Automatic snapshots, a Backups dialog to restore them, and JSON export and import

## Run it

Open `index.html` in a browser. There is no build step and nothing to install.

Data is stored in the browser's local storage for the file's location. Use **Export** to keep a copy elsewhere.

## Test

`./smoke-test.sh` drives the page with [agent-browser](https://github.com/vercel-labs/agent-browser). It uses an isolated storage key (`?store=smoke`), so it never touches real data.
