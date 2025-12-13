<%*

// Get the entire current file content

const content = await tp.file.content;

  

// This will use the actual current date and time when you run it in Obsidian.

const now = new Date();

const today = now.toISOString().split("T")[0];

  

// Prepare the sections to hold the sorted tasks

const sections = {

doneAll: [],

pastDue: [],

futureTasks: [],

doneToday: [],

dueToday: []

};

  

// --- CORE LOGIC CHANGE ---

// We no longer check if the file is already organized.

// Instead, we process every single line and only pick out the ones that are tasks.

// Old headers, separators, and blank lines are ignored.

  

content.split("\n").forEach(line => {

const trimmedLine = line.trim();

// Regex to find a valid task line

const match = trimmedLine.match(/^- \[( |x)\](.*)@(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})$/);

// If the line is a task, sort it. If not, IGNORE it.

if (match) {

const [_, status, taskText, date, time] = match;

const isDone = status === "x";

const isToday = date === today;

const isPast = date < today;

const isFuture = date > today;

if (isDone) {

if (isToday) {

sections.doneToday.push(trimmedLine);

} else {

sections.doneAll.push(trimmedLine);

}

} else {

if (isToday) {

sections.dueToday.push(trimmedLine);

} else if (isPast) {

sections.pastDue.push(trimmedLine);

} else if (isFuture) {

sections.futureTasks.push(trimmedLine);

}

}

}

});

  

// --- REBUILD THE FILE FROM SCRATCH ---

  

// Generate new organized content

let output = "";

  

const addSection = (title, items) => {

// Only create a section if it has tasks in it

if (items.length > 0) {

// Sort items alphabetically within each section for consistency

items.sort();

output += `### ${title}:\n\n---\n\n${items.join("\n")}\n\n`;

}

};

  

// Add each section back in your desired order.

// NOTE: I have also corrected the order to match your last request.

addSection("ALL DONE Tasks", sections.doneAll);

addSection("GENERAL (past due) Tasks", sections.pastDue);

addSection("FUTURE Tasks", sections.futureTasks);

addSection("DONE Today", sections.doneToday);

addSection("DUE Today", sections.dueToday);

  

// Replace the entire file content with the newly organized output.

await app.vault.modify(tp.config.target_file, output.trim());

  

// Return an empty string so Templater doesn't insert any extra text.

return "";

%>