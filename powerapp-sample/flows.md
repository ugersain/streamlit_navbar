# Flows for the sample app

## Flow 1: DB2ReportFlow (called by "Run Db2 report & email")

Trigger: **Power Apps (V2)**, text input `RunDate` (yyyy-MM-dd).

1. **Initialize variable** `html` (String) = empty.
2. For each query (repeat per query):
   - IBM DB2 connector: **Get rows** (or a stored procedure / view taking the date).
     Filter e.g. `BUSINESS_DATE eq '@{triggerBody()?['text']}'`.
   - **Condition**: `length(body('Get_rows')?['value'])` is greater than 0
     - Yes: **Create HTML table** from `body('Get_rows')?['value']`,
       then **Append to string variable** `html` = `<h3>Query 1 ✔</h3>` + table output.
     - No:  **Append to string variable** `html` = `<h3>Query 1 ⚠</h3><p>No rows for @{triggerBody()?['text']}</p>`
3. **Send an email (V2)**
   - Subject: `Db2 report for @{triggerBody()?['text']}`
   - Body: `@{variables('html')}` (switch the body editor to code view `</>`)
4. **Respond to a PowerApp or flow** (text output `status`) = `Sent`.

Note: IBM DB2 is a Premium connector; on-premises Db2 needs an on-premises data gateway.

## Flow 2: WeeklyCalendarFlow (called by "Send weekly UAT/SIT mail")

Trigger: **Power Apps (V2)**, no inputs.

1. **Get items** (SharePoint calendar list), Filter Query:
   ```
   EventDate ge '@{startOfWeek(utcNow())}' and EventDate lt '@{addDays(startOfWeek(utcNow()),7)}'
   ```
   Use "Send an HTTP request to SharePoint" with CAML `ExpandRecurrence` if events recur.
2. **Filter array** "UAT" (From: value of Get items, advanced mode):
   ```
   @not(empty(intersection(
     split(replace(replace(replace(toUpper(coalesce(item()?['Location'],'')),' ',','),'/',','),';',','),','),
     createArray('A','B'))))
   ```
3. **Filter array** "SIT": same expression with `createArray('I','F')`.
4. **Create HTML table** x2 (from each Filter array body).
   Custom columns: Title = `item()?['Title']`, Start = `formatDateTime(item()?['EventDate'],'dd MMM HH:mm')`,
   End = `formatDateTime(item()?['EndDate'],'dd MMM HH:mm')`, Env = `item()?['Location']`.
5. **Send an email (V2)**
   - Subject: `Weekly UAT/SIT schedule - w/c @{formatDateTime(startOfWeek(utcNow()),'dd MMM yyyy')}`
   - Body:
     ```
     <h2>UAT (A, B)</h2>
     @{if(empty(body('Filter_array_UAT')),'<p>No events</p>',body('Create_HTML_table_UAT'))}
     <h2>SIT (I, F)</h2>
     @{if(empty(body('Filter_array_SIT')),'<p>No events</p>',body('Create_HTML_table_SIT'))}
     ```
6. **Respond to a PowerApp or flow**: text output `status` = `Sent`.

Optional: add a **Recurrence** trigger (Mondays 8:00) to a copy of this flow for fully automatic sending.

## Wiring it up in Power Apps Studio
1. Create a blank canvas app (Tablet).
2. Add both flows: Power Automate pane -> Add flow. Names must match `DB2ReportFlow` and `WeeklyCalendarFlow`.
3. Right-click the screen tree -> Paste code (or open scrHome, then paste `scrHome.pa.yaml`).
   If a control type fails to paste, insert it from the Insert menu and copy the properties across.
4. Play the app (F5) and click each button.
