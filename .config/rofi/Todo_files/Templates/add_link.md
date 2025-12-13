<%*

// This script prompts for a URL, fetches the page's title,

// and appends a formatted Markdown link to the end of the current file.

  

// 1. GET USER INPUT

// Prompt the user to enter a URL.

const url = await tp.system.prompt("Enter URL to add:");

  

// If the user cancels or enters nothing, exit the script silently.

if (!url) {

return "";

}

  

// A simple check to ensure the input looks like a URL.

if (!url.startsWith('http://') && !url.startsWith('https://')) {

new Notice("❌ Invalid URL format.", 3000); // Show an error notification.

return "";

}

  
  

// 2. FETCH THE WEBPAGE TITLE

// Show a notification to let the user know the script is working.

new Notice(`⏳ Fetching title for ${url}...`);

  

let pageTitle;

  

try {

// Use Templater's built-in request function to fetch the webpage's HTML.

// This is safer and more integrated than using external commands.

const htmlContent = await tp.obsidian.request({ url: url });

  

// Use a regular expression to find the content inside the <title> tag.

// This is more robust than simple string matching.

const titleMatch = htmlContent.match(/<title>([^<]*)<\/title>/i);

  

if (titleMatch && titleMatch[1]) {

// If a title is found, use it.

pageTitle = titleMatch[1].trim();

}

  

} catch (error) {

// If the request fails (e.g., network error, 404), log it and proceed.

console.error("Templater - Add Link Error:", error);

}

  
  

// 3. PREPARE THE LINK

// If fetching the title failed for any reason, use the domain name as a fallback.

if (!pageTitle) {

try {

const urlObject = new URL(url);

pageTitle = urlObject.hostname;

new Notice("⚠️ Title not found. Using domain name instead.", 3000);

} catch (e) {

// If the URL is fundamentally invalid, use the raw input as a last resort.

pageTitle = url;

}

}

  

// Sanitize the title by removing any characters that would break Markdown link syntax.

const sanitizedTitle = pageTitle.replace(/\[/g, '(').replace(/\]/g, ')');

  

// Create the final Markdown-formatted link string.

const markdownLink = `- [${sanitizedTitle}](${url})`;

  
  

// 4. APPEND THE LINK TO THE CURRENT FILE

// Get the current file object.

const file = tp.config.target_file;

  

// Read the existing content of the file.

const content = await app.vault.read(file);

  

let newContent;

  

if (content.trim() === '') {

// If the file is empty, the new link is the only content.

newContent = markdownLink;

} else {

// If the file has content, add the new link to the very end, on a new line.

// trimEnd() ensures we don't add extra blank lines if the file already ends with one.

newContent = content.trimEnd() + '\n' + markdownLink;

}

  

// Use the Obsidian API to overwrite the file with the updated content.

await app.vault.modify(file, newContent);

  

// Show a final confirmation notification.

new Notice(`✅ Link added: ${sanitizedTitle}`);

  
  

// 5. RETURN EMPTY STRING

// This is crucial! It tells Templater that we are done and prevents it

// from inserting any extra text at the cursor's current position.

return "";

%>