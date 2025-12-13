module.exports = async (tp) => {
  const raw = await tp.file.read();

  const now = new Date();
  const today = now.toISOString().split("T")[0];

  const doneToday = [];
  const doneAll = [];
  const dueToday = [];
  const generalPastDue = [];

  const lines = raw.split("\n");

  for (let line of lines) {
    let match = line.match(/^- \[( |x)\] .*?@(\d{4}-\d{2}-\d{2}) \d{2}:\d{2}$/);
    if (!match) continue;

    let status = match[1] === "x" ? "done" : "todo";
    let date = match[2];

    let taskDate = new Date(date);
    let isToday = date === today;
    let isPast = taskDate < now;

    if (status === "done") {
      if (isToday) {
        doneToday.push(line);
      } else {
        doneAll.push(line);
      }
    } else {
      if (isToday) {
        dueToday.push(line);
      } else if (isPast) {
        generalPastDue.push(line);
      }
    }
  }

  function section(title, tasks) {
    return `### ${title}:\n-------------------\n${tasks.length ? tasks.join("\n") : "*None*"}\n`;
  }

  const finalContent =
    section("..DONE All", doneAll) +
    "\n" +
    section("General tasks (past due)", generalPastDue) +
    "\n" +
    section("DONE TODAY", doneToday) +
    "\n" +
    section("..due today", dueToday);

  await app.vault.modify(tp.file, finalContent);
};
