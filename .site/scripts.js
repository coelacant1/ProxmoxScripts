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

// Parse the top comment block from script content and remove # symbols
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
      // Remove the # symbol and any leading/trailing whitespace
      const cleanedLine = line.replace(/^#\s?/, '').trim();
      commentBlock.push(cleanedLine);
    } else if (inCommentBlock) {
      break; // stop at first non-comment line after comments
    }
  }

  const parsedComment = commentBlock.join('\n') || 'No description available.';
  console.log('[DEBUG] Parsed comment block:', parsedComment);
  return parsedComment;
}

// Extract just the description part (text between script name and "Usage:")
function parseDescription(content) {
  const fullComment = parseTopComment(content);
  const lines = fullComment.split('\n');
  const descriptionLines = [];
  let foundScriptName = false;

  for (const line of lines) {
    // Skip empty lines and the script name line (.sh)
    if (line.endsWith('.sh')) {
      foundScriptName = true;
      continue;
    }
    
    // Stop at Usage:, Arguments:, Examples:, Function Index:, etc.
    if (line.match(/^(Usage|Arguments|Examples|Function Index|Options):/i)) {
      break;
    }
    
    // Collect description lines after script name
    if (foundScriptName && line.trim()) {
      descriptionLines.push(line);
    }
  }

  return descriptionLines.join('\n').trim() || 'No description available.';
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

async function fetchDescription(filePath) {
  const apiURL = `${baseApiURL}/${filePath}`;
  console.log(`[DEBUG] fetchDescription(): ${apiURL}`);

  try {
    const response = await fetch(apiURL);
    if (!response.ok) {
      throw new Error(`[ERROR] Failed to fetch script content. Status: ${response.status}`);
    }
    const data = await response.json();
    const decoded = atob(data.content);
    return parseDescription(decoded);
  } catch (err) {
    console.error(err);
    return 'Unable to load description.';
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
  
  // Check if this is CCPVE.sh (the only script that can be run standalone)
  const isCCPVE = file === 'CCPVE.sh';

  // Unique IDs for info and full script sections
  const infoId = `info-${filePath.replace(/[\/.]/g, '-')}`;
  const fullScriptId = `full-${filePath.replace(/[\/.]/g, '-')}`;

  // Create table container
  const table = document.createElement('table');
  table.classList.add('file-block-table');

  // Unique ID for description preview
  const descId = `desc-${filePath.replace(/[\/.]/g, '-')}`;

  // Build button HTML - only show copy button for CCPVE.sh
  const buttonsHTML = isCCPVE 
    ? `<button class="copy-button">Copy Command</button>
       <button class="info-button">Show Help</button>
       <button class="script-button">Show Full Script</button>
       <a href="https://github.com/${repoOwner}/${repoName}/blob/main/${filePath}" target="_blank" rel="noopener noreferrer" class="github-link" title="View on GitHub">
         <button class="github-button">GitHub</button>
       </a>`
    : `<button class="info-button">Show Help</button>
       <button class="script-button">Show Full Script</button>
       <a href="https://github.com/${repoOwner}/${repoName}/blob/main/${filePath}" target="_blank" rel="noopener noreferrer" class="github-link" title="View on GitHub">
         <button class="github-button">GitHub</button>
       </a>`;

  // Build command/description display HTML
  const contentHTML = isCCPVE 
    ? `<pre><code class="language-bash">${command}</code></pre>` 
    : `<pre><code class="script-description" id="${descId}">Loading description...</code></pre>`;

  // Construct table rows
  table.innerHTML = `
    <tr>
      <td class="file-name-cell">
        ${formattedName}
        <div class="script-path">${filePath}</div>
      </td>
      <td class="buttons-cell">
        ${buttonsHTML}
      </td>
    </tr>
    <tr>
      <td colspan="3" class="script-command-cell">
        ${contentHTML}
        <div class="file-info hidden" id="${infoId}"></div>
        <div class="full-script hidden" id="${fullScriptId}"></div>
      </td>
    </tr>
  `;

  // Fetch and display description for non-CCPVE scripts
  if (!isCCPVE) {
    fetchDescription(filePath).then(description => {
      const descDiv = table.querySelector(`#${descId}`);
      if (descDiv) {
        descDiv.textContent = description;
      }
    });
  }

  // Attach event listeners for buttons
  const copyBtn = table.querySelector('.copy-button');
  const infoBtn = table.querySelector('.info-button');
  const scriptBtn = table.querySelector('.script-button');
  const infoDiv = table.querySelector(`#${infoId}`);
  const fullDiv = table.querySelector(`#${fullScriptId}`);

// Only add copy button listener if it exists (CCPVE.sh only)
if (copyBtn) {
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
}


// Inside the Show/Hide Help button event listener
infoBtn.addEventListener('click', async () => {
  const isHidden = infoDiv.classList.contains('hidden');
  console.log(`[DEBUG] Help button clicked. isHidden=${isHidden}`);
  if (isHidden) {
    // Show help and hide full script if visible
    if (!fullDiv.classList.contains('hidden')) {
      fullDiv.classList.add('hidden');
      scriptBtn.textContent = 'Show Full Script';
      scriptBtn.setAttribute('aria-expanded', 'false');
    }
    
    infoBtn.textContent = 'Hide Help';
    infoBtn.setAttribute('aria-expanded', 'true');
    infoDiv.classList.remove('hidden');

    // Only fetch if not already loaded
    if (!infoDiv.textContent.trim()) {
      const content = await fetchTopComment(filePath);
      // Don't wrap in bash code block, use plain text styling
      infoDiv.innerHTML = `<pre><code class="language-plaintext">${content}</code></pre>`;
      // Apply Prism highlighting
      Prism.highlightElement(infoDiv.querySelector('code'));
    }
  } else {
    // Hide help
    infoBtn.textContent = 'Show Help';
    infoBtn.setAttribute('aria-expanded', 'false');
    infoDiv.classList.add('hidden');
  }
});

// Show/Hide Full Script button event listener
scriptBtn.addEventListener('click', async () => {
  const isHidden = fullDiv.classList.contains('hidden');
  console.log(`[DEBUG] Full script button clicked. isHidden=${isHidden}`);
  if (isHidden) {
    // Show script and hide help if visible
    if (!infoDiv.classList.contains('hidden')) {
      infoDiv.classList.add('hidden');
      infoBtn.textContent = 'Show Help';
      infoBtn.setAttribute('aria-expanded', 'false');
    }
    
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
 * Global Script Index for Search
 *************************************************************************/
let globalScriptIndex = [];

// Recursively fetch all scripts in the repository
async function buildGlobalScriptIndex() {
  const excludedScripts = ['MakeScriptsExecutable.sh', 'UpdateProxmoxScripts.sh', 'CCPVEOffline.sh'];
  const scripts = [];
  
  async function scanDirectory(path = '') {
    const contents = await fetchRepoStructure(path);
    
    for (const item of contents) {
      // Skip hidden items
      if (item.name.startsWith('.')) continue;
      
      if (item.type === 'dir') {
        // Recursively scan subdirectories
        await scanDirectory(path ? `${path}/${item.name}` : item.name);
      } else if (item.type === 'file' && item.name.endsWith('.sh')) {
        // Skip excluded scripts
        if (excludedScripts.includes(item.name)) continue;
        
        const filePath = path ? `${path}/${item.name}` : item.name;
        scripts.push({
          name: item.name,
          path: filePath,
          folder: path || 'root'
        });
      }
    }
  }
  
  await scanDirectory();
  return scripts;
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

    // Handle images to prevent CORS errors
    tempDiv.querySelectorAll('img').forEach((img) => {
      const src = img.getAttribute('src');
      if (src) {
        // Convert relative paths to absolute GitHub raw URLs
        if (src.startsWith('./') || src.startsWith('../') || (!src.startsWith('http://') && !src.startsWith('https://'))) {
          const cleanPath = src.replace(/^\.\//, '').replace(/^\.\.\//, '');
          img.setAttribute('src', `${baseRawURL}/${cleanPath}`);
        }
        // Add error handler to hide broken images
        img.setAttribute('onerror', 'this.style.display="none"');
        img.setAttribute('loading', 'lazy');
      }
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

  // Add breadcrumb navigation
  const breadcrumb = document.createElement('div');
  breadcrumb.classList.add('breadcrumb');
  const pathParts = path ? path.split('/') : [];
  let breadcrumbHTML = '<a href="#" class="breadcrumb-link" data-path="">Home</a>';
  
  let currentPath = '';
  for (const part of pathParts) {
    currentPath = currentPath ? `${currentPath}/${part}` : part;
    breadcrumbHTML += ` <span class="breadcrumb-separator">›</span> <a href="#" class="breadcrumb-link" data-path="${currentPath}">${part}</a>`;
  }
  
  breadcrumb.innerHTML = breadcrumbHTML;
  content.appendChild(breadcrumb);
  
  // Attach click handlers to breadcrumb links
  breadcrumb.querySelectorAll('.breadcrumb-link').forEach(link => {
    link.addEventListener('click', (e) => {
      e.preventDefault();
      renderContent(link.getAttribute('data-path'));
    });
  });

  // Add search box at the top level only
  if (!path) {
    const searchContainer = document.createElement('div');
    searchContainer.classList.add('search-container');
    searchContainer.innerHTML = `
      <input type="text" id="script-search" placeholder="Search scripts..." />
    `;
    content.appendChild(searchContainer);
  }

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

  // Add search functionality - always show it and make it global
  const searchInput = document.getElementById('script-search');
  if (searchInput && !path) {
    // Build index on first load
    if (globalScriptIndex.length === 0) {
      console.log('[DEBUG] Building global script index...');
      globalScriptIndex = await buildGlobalScriptIndex();
      console.log(`[DEBUG] Indexed ${globalScriptIndex.length} scripts`);
    }

    searchInput.addEventListener('input', async (e) => {
      const searchTerm = e.target.value.toLowerCase().trim();
      
      if (searchTerm === '') {
        // No search term - show current directory view
        renderContent(path);
        return;
      }
      
      // Search globally through all scripts
      const results = globalScriptIndex.filter(script => 
        script.name.toLowerCase().includes(searchTerm) || 
        script.path.toLowerCase().includes(searchTerm)
      );
      
      // Clear and show search results
      content.innerHTML = '';
      
      // Re-add search box
      const searchContainer = document.createElement('div');
      searchContainer.classList.add('search-container');
      searchContainer.innerHTML = `
        <input type="text" id="script-search" value="${searchTerm}" placeholder="Search scripts..." />
      `;
      content.appendChild(searchContainer);
      
      // Show results count
      const resultsHeader = document.createElement('div');
      resultsHeader.style.cssText = 'padding: 1em; color: #f8cbdd; font-size: 0.9em;';
      resultsHeader.textContent = `Found ${results.length} script${results.length !== 1 ? 's' : ''}`;
      content.appendChild(resultsHeader);
      
      const resultsList = document.createElement('ul');
      
      for (const script of results) {
        const li = document.createElement('li');
        const block = createScriptBlock(script.folder === 'root' ? '' : script.folder, script.name);
        li.appendChild(block);
        resultsList.appendChild(li);
      }
      
      content.appendChild(resultsList);
      
      // Re-attach event listener to the new search input
      const newSearchInput = document.getElementById('script-search');
      if (newSearchInput) {
        newSearchInput.focus();
        newSearchInput.addEventListener('input', arguments.callee);
      }
    });
  }

  if (!path) {
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
