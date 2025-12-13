<%*

// 1. GET USER INPUT
const input = await tp.system.prompt("Enter task: (-h|-n|-l) (-c color) text with optional #tags");

if (!input) return "";

// 2. PARSE FLAGS AND MESSAGE
let msg = input;
let prio = "@Prio(normal)";
let colorTag = "";

// Priority
const prioMatch = msg.match(/^(-h|-n|-l)\s/);
if (prioMatch) {
  const flag = prioMatch[1];
  if (flag === '-h') prio = "@Prio(high)";
  if (flag === '-l') prio = "@Prio(low)";
  msg = msg.replace(prioMatch[0], '');
}

// Color
const colorMatch = msg.match(/-c\s+(\w+)\s?/);
if (colorMatch) {
  const colorName = colorMatch[1];
  colorTag = `@Color(${colorName})`;
  msg = msg.replace(colorMatch[0], '');
}

// Tags
const tagRegex = /#(\w+)/g;
let tagMatch;
let tagsFromInput = [];
while ((tagMatch = tagRegex.exec(msg)) !== null) {
  tagsFromInput.push(`@Tag(${tagMatch[1]})`);
}
// Remove #tags from message text
msg = msg.replace(tagRegex, '').trim();

// 3. ASSEMBLE THE TASK STRING
const now = window.moment().format("YYYY-MM-DD HH:mm");
const allTags = [prio, colorTag, ...tagsFromInput].filter(Boolean).join(' ');
const task = `- [ ] ${allTags} ${msg} @${now}`;

// 4. APPEND TASK TO THE FILE
const file = tp.config.target_file;
const content = await app.vault.read(file);
const newContent = content.trimEnd() + '\n' + task;
await app.vault.modify(file, newContent);

return "";
%>
