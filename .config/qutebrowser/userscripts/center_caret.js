(function () {
  try {
    const centerX = window.innerWidth / 2;
    const centerY = window.innerHeight / 2;
    const element = document.elementFromPoint(centerX, centerY);
    if (!element) {
      return;
    }
    const sel = window.getSelection();
    if (!sel) {
      return;
    }
    sel.removeAllRanges();
    function findFirstTextNode(startNode) {
      const walker = document.createTreeWalker(
        startNode,
        NodeFilter.SHOW_TEXT,
        null,
      );
      let node;
      while ((node = walker.nextNode())) {
        if (node.nodeValue.trim() !== "") {
          return node;
        }
      }
      return null;
    }
    const targetNode = findFirstTextNode(element) || element;
    const range = document.createRange();
    range.setStart(targetNode, 0);
    range.collapse(true);
    sel.addRange(range);
    element.scrollIntoView({ block: "center", inline: "nearest" });
  } catch (e) {
    // Fail silently
  }
})();
