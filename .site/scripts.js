/*************************************************************************
 * Configuration and Setup
 *************************************************************************/
const repoOwner = 'coelacant1';
const repoName = 'ProxmoxScripts';
const baseApiURL = `https://api.github.com/repos/${repoOwner}/${repoName}/contents`;
const baseRawURL = `https://github.com/${repoOwner}/${repoName}/raw/main`;

const content = document.getElementById('content');

/*************************************************************************
 * Utilities
 *************************************************************************/

// Format .sh name => "Bulk Add IP Note to V Ms", etc.
function formatFileName(fileName) {
  return fileName
    .replace(/\.sh$/i, '') // Remove the .sh extension (case-insensitive)
    // Insert space between a lowercase letter or number and an uppercase letter
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    // Insert space between consecutive uppercase letters followed by a lowercase letter
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2')
    // Insert space between a lowercase letter and a number, if needed
    .replace(/([a-zA-Z])([0-9])/g, '$1 $2')
    // Insert space between a number and a lowercase letter, if needed
    .replace(/([0-9])([a-z])/g, '$1 $2')
    .replace(/\bV Ms\b/g, 'VMs') // Special case: "V Ms" becomes "VMs"
    .replace(/\bIS Os\b/g, 'ISOs') // Special case
    .replace(/\bOS Ds\b/g, 'OSDs') // Special case
    .replace(/\bTTYS 0\b/g, 'TTYS0') // Special case
    .trim();
}

// Parse the top comment block from script content
function parseTopComment(content) {
  console.log('[DEBUG] Parsing script content for top comment...');
  const lines = content.split('\n');
  const commentBlock = [];
  let inCommentBlock = false;

  for (const line of lines) {
    if (line.startsWith('#!')) {
      // Skip shebang
      continue;
    } else if (line.startsWith('#')) {
      inCommentBlock = true;
      commentBlock.push(line.replace(/^\s*/, '').trim());
    } else if (inCommentBlock) {
      break; // stop at first non-comment line after comments
    }
  }

  const parsedComment = commentBlock.join('\n') || 'No description available.';
  console.log('[DEBUG] Parsed comment block:', parsedComment);
  return parsedComment;
}

/*************************************************************************
 * Fetching Script Content from GitHub
 *************************************************************************/
async function fetchTopComment(filePath) {
  const apiURL = `${baseApiURL}/${filePath}`;
  console.log(`[DEBUG] fetchTopComment(): ${apiURL}`);

  try {
    const response = await fetch(apiURL);
    if (!response.ok) {
      throw new Error(`[ERROR] Failed to fetch script content. Status: ${response.status}`);
    }
    const data = await response.json();
    const decoded = atob(data.content);
    return parseTopComment(decoded);
  } catch (err) {
    console.error(err);
    return 'Unable to load script information.';
  }
}

async function fetchFullScript(filePath) {
  const apiURL = `${baseApiURL}/${filePath}`;
  console.log(`[DEBUG] fetchFullScript(): ${apiURL}`);

  try {
    const response = await fetch(apiURL);
    if (!response.ok) {
      throw new Error(`[ERROR] Failed to fetch full script. Status: ${response.status}`);
    }
    const data = await response.json();
    const decoded = atob(data.content);
    return decoded;
  } catch (err) {
    console.error(err);
    return 'Unable to load full script.';
  }
}

let cachedReadmeHTML = null; // cache so we only parse once

async function getRepositoryReadmeHTML() {
  if (cachedReadmeHTML) return cachedReadmeHTML;

  const readmeApiUrl = `${baseApiURL}/README.md`;
  try {
    const response = await fetch(readmeApiUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch README. Status: ${response.status}`);
    }
    const data = await response.json();
    const decoded = atob(data.content);

    // Turn the Markdown into highlighted HTML
    const finalHTML = parseMarkdownWithPrism(decoded);
    cachedReadmeHTML = finalHTML;
    return finalHTML;
  } catch (err) {
    console.error(err);
    return '<p>Unable to load README.md.</p>';
  }
}

/*************************************************************************
 * Creating Each Script Block
 *************************************************************************/
function createScriptBlock(folder, file) {
  // Determine raw GitHub URL
  const filePath = folder ? `${folder}/${file}` : file;
  const fileURL = `${baseRawURL}/${filePath}`;
  const command = `bash -c "$(wget -qLO - https://github.com/${repoOwner}/${repoName}/raw/main/${filePath})"`;
  const formattedName = formatFileName(file);

  // Unique IDs for info and full script sections
  const infoId = `info-${filePath.replace(/[\/.]/g, '-')}`;
  const fullScriptId = `full-${filePath.replace(/[\/.]/g, '-')}`;

  // Create table container
  const table = document.createElement('table');
  table.classList.add('file-block-table'); // Add a specific class for styling

  // Construct table rows
  table.innerHTML = `
    <tr>
      <td class="file-name-cell">${formattedName}</td>
      <td class="buttons-cell">
        <button class="copy-button">Copy Command</button>
        <button class="info-button">Show Info</button>
        <button class="script-button">Show Full Script</button>
      </td>
    </tr>
    <tr>
      <td colspan="3" class="script-command-cell">
        <pre><code class="language-bash">${command}</code></pre>
        <div class="file-info hidden" id="${infoId}"></div>
        <div class="full-script hidden" id="${fullScriptId}"></div>
      </td>
    </tr>
  `;

  // Attach event listeners for buttons
  const copyBtn = table.querySelector('.copy-button');
  const infoBtn = table.querySelector('.info-button');
  const scriptBtn = table.querySelector('.script-button');
  const infoDiv = table.querySelector(`#${infoId}`);
  const fullDiv = table.querySelector(`#${fullScriptId}`);

copyBtn.addEventListener('click', () => {
  console.log('[DEBUG] Copy button clicked:', command);

  // Find the <code> element within the same container
  const codeBlock = copyBtn.closest('.file-block-table').querySelector('code');

  // Copy the command to the clipboard
  navigator.clipboard.writeText(command).then(() => {
    // Provide feedback on the button
    copyBtn.textContent = 'Copied!';
    copyBtn.classList.add('copied');

    // Add highlight animation to the code block
    if (codeBlock) {
      codeBlock.classList.add('code-highlight');

      // Remove the highlight class after the animation ends
      setTimeout(() => {
        codeBlock.classList.remove('code-highlight');
        copyBtn.textContent = 'Copy Command';
        copyBtn.classList.remove('copied');
      }, 1000); // Match the duration of the animation
    }
  }).catch((err) => {
    console.error('Failed to copy text:', err);
    copyBtn.textContent = 'Error!';
    setTimeout(() => {
      copyBtn.textContent = 'Copy Command';
      copyBtn.classList.remove('copied');
    }, 2000);
  });
});
  

// Inside the Show/Hide Info button event listener
infoBtn.addEventListener('click', async () => {
  const isHidden = infoDiv.classList.contains('hidden');
  console.log(`[DEBUG] Info button clicked. isHidden=${isHidden}`);
  if (isHidden) {
    // Show info
    infoBtn.textContent = 'Hide Info';
    infoBtn.setAttribute('aria-expanded', 'true');
    infoDiv.classList.remove('hidden');

    // Only fetch if not already loaded
    if (!infoDiv.textContent.trim()) {
      const content = await fetchTopComment(filePath);
      
      infoDiv.innerHTML = `<pre><code class="language-bash">${content}</code></pre>`;
      // Apply Prism highlighting
      Prism.highlightElement(infoDiv.querySelector('code'));
    }
  } else {
    // Hide info
    infoBtn.textContent = 'Show Info';
    infoBtn.setAttribute('aria-expanded', 'false');
    infoDiv.classList.add('hidden');
  }
});

// Similarly for the Show/Hide Full Script button
scriptBtn.addEventListener('click', async () => {
  const isHidden = fullDiv.classList.contains('hidden');
  console.log(`[DEBUG] Full script button clicked. isHidden=${isHidden}`);
  if (isHidden) {
    // Show script
    scriptBtn.textContent = 'Hide Full Script';
    scriptBtn.setAttribute('aria-expanded', 'true');
    fullDiv.classList.remove('hidden');

    // Only fetch if not already loaded
    if (!fullDiv.innerHTML.trim()) {
      const content = await fetchFullScript(filePath);
      fullDiv.innerHTML = `<pre><code class="language-bash">${content}</code></pre>`;
      // Apply Prism highlighting
      Prism.highlightElement(fullDiv.querySelector('code'));
    }
  } else {
    // Hide script
    scriptBtn.textContent = 'Show Full Script';
    scriptBtn.setAttribute('aria-expanded', 'false');
    fullDiv.classList.add('hidden');
  }
});


  return table;
}


function createDownloadRepoBlock() {
    // Command to clone or download the repo
    const command = `git clone https://github.com/coelacant1/ProxmoxScripts.git`;
  
    // Create a container
    const container = document.createElement('table');
    container.classList.add('file-block-table'); // Reuse your .file-block styling if desired

    // Set up the innerHTML with explicit block-level elements
    container.innerHTML = `
      <tr>
        <td class="file-name-cell">Download Repository</td>
        <td class="buttons-cell">
          <button class="copy-button">Copy Command</button>
        </td>
      </tr>
      <tr>
        <td colspan="3" class="script-command-cell">
        <pre><code class="language-bash">${command}</code></pre>
        </td>
      </tr>
    `;
  
    // Attach a direct event listener for the copy button
  const copyBtn = container.querySelector('.copy-button');
  copyBtn.addEventListener('click', () => {
    const codeBlock = container.querySelector('code'); // Find the <code> element inside the container
    const command = codeBlock.textContent; // Get the text content of the <code> element

    // Copy the command to the clipboard
    navigator.clipboard.writeText(command).then(() => {
        // Provide feedback on the button
        copyBtn.textContent = 'Copied!';
        copyBtn.classList.add('copied');

        // Add highlight animation to the code block
        codeBlock.classList.add('code-highlight');

        // Remove highlight and reset button text after the animation ends
        setTimeout(() => {
            codeBlock.classList.remove('code-highlight');
            copyBtn.textContent = 'Copy Command';
            copyBtn.classList.remove('copied');
        }, 1000); // Match the animation duration
    }).catch((err) => {
        console.error('Failed to copy text:', err);
        copyBtn.textContent = 'Error!';
        setTimeout(() => {
            copyBtn.textContent = 'Copy Command';
        }, 2000);
    });
  });
  
    return container;
  }
  
  

/*************************************************************************
 * Fetching Directory Structure & Rendering
 *************************************************************************/
async function fetchRepoStructure(path = '') {
  const apiURL = `${baseApiURL}/${path}`;
  console.log(`[DEBUG] fetchRepoStructure(): ${apiURL}`);
  try {
    const res = await fetch(apiURL);
    if (!res.ok) throw new Error(`[ERROR] Failed to fetch directory. Status: ${res.status}`);
    return await res.json();
  } catch (err) {
    console.error(err);
    return [];
  }
}

function parseMarkdownWithPrism(markdown) {
    // Convert Markdown to HTML (using Marked or your chosen Markdown parser)
    const html = marked.parse(markdown);
  
    // Create a temporary container to apply Prism highlighting
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
  
    // Highlight each code block with Prism
    tempDiv.querySelectorAll('pre code').forEach((codeBlock) => {
      Prism.highlightElement(codeBlock);
    });
  
    // Return the updated HTML
    return tempDiv.innerHTML;
  }
  

async function showRepositoryReadme() {
// This function is presumably called in `renderContent()` or similar
const readmeContainer = document.createElement('div');
readmeContainer.classList.add('readme-container'); // or similar styling

const readmeHTML = await getRepositoryReadmeHTML();
readmeContainer.innerHTML = readmeHTML;  // directly set the HTML

return readmeContainer;
}

// Render the root or any subfolder
async function renderContent(path = '') {
  console.log(`[DEBUG] renderContent(): path="${path}"`);
  const contents = await fetchRepoStructure(path);
  console.log('[DEBUG] Directory contents:', contents);

  // Clear current content
  content.innerHTML = '';

  // Filter out hidden items (starting with .)
  const visibleItems = contents.filter((item) => !item.name.startsWith('.'));

  // Sort: dirs first, files second
  visibleItems.sort((a, b) => {
    if (a.type === b.type) return a.name.localeCompare(b.name);
    return a.type === 'dir' ? -1 : 1;
  });

  // Create a simple list
  const list = document.createElement('ul');

  // If not root, add a back link
  if (path) {
    const parentPath = path.split('/').slice(0, -1).join('/');
    const backItem = document.createElement('li');
    backItem.innerHTML = `<a href="#" class="back-link">../</a>`;
    backItem.querySelector('a').addEventListener('click', () => {
      renderContent(parentPath);
    });
    list.appendChild(backItem);
  }

  // List of scripts to exclude
  const excludedScripts = ['MakeScriptsExecutable.sh', 'UpdateProxmoxScripts.sh', 'CCPVEOffline.sh'];

  // Populate folders/files
  for (const item of visibleItems) {
    if (item.type === 'dir') {
      // Folder
      const li = document.createElement('li');
      li.innerHTML = `<a href="#" class="folder-link">/${item.name}</a>`;
      li.querySelector('a').addEventListener('click', () => {
        renderContent(path ? `${path}/${item.name}` : item.name);
      });
      list.appendChild(li);
    } else if (item.type === 'file' && item.name.endsWith('.sh')) {
      // Skip excluded scripts
      if (excludedScripts.includes(item.name)) continue;

      // Script
      const li = document.createElement('li');
      const block = createScriptBlock(path, item.name);
      li.appendChild(block);
      list.appendChild(li);
    }
  }

  content.appendChild(list);

  if (!path) {
    // we are at root, so show the "Download Repository" block
    const downloadBlock = createDownloadRepoBlock();
    content.appendChild(downloadBlock);
  }

  // near the end of renderContent()
  const readmeDiv = await showRepositoryReadme();
  content.appendChild(readmeDiv);

}

/*************************************************************************
 * On Page Load
 *************************************************************************/
document.addEventListener('DOMContentLoaded', () => {
  renderContent(); // Render root directory
});
