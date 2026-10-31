(function(global) {
  "use strict";
  var copyButtonLabel = window.__yamabikoCopyButtonLabel || "Copy";

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/`/g, "&#96;");
  }

  function safeHref(rawUrl) {
    var url = String(rawUrl || "").trim();
    if (!url) return null;
    var unescaped = url.replace(/&amp;/g, "&");
    if (!/^https?:\/\//i.test(unescaped)) return null;
    return escapeAttr(unescaped);
  }

  function externalArrow() {
    return '<span class="yamabiko-external-arrow" aria-hidden="true">↗</span>';
  }

  function externalLinkHtml(safeUrl, label, labelAlreadyHasArrow) {
    var arrow = labelAlreadyHasArrow ? "" : " " + externalArrow();
    return '<a href="' + safeUrl + '">' + label + arrow + "</a>";
  }

  function bareUrlLabel(rawUrl) {
    var match = String(rawUrl || "").match(/^https?:\/\/(?:www\.)?([^\/?#:]+)(?::\d+)?/i);
    return match && match[1] ? match[1] : rawUrl;
  }

  function splitTrailingUrlPunctuation(rawUrl) {
    var url = String(rawUrl || "");
    var suffix = "";
    var alwaysTrailing = /[.,!?;:、。！？；：]$/;

    while (url && alwaysTrailing.test(url)) {
      suffix = url.slice(-1) + suffix;
      url = url.slice(0, -1);
    }

    var bracketPairs = [
      ["(", ")"], ["[", "]"], ["{", "}"],
      ["（", "）"], ["「", "」"], ["『", "』"]
    ];
    bracketPairs.forEach(function(pair) {
      var opening = pair[0];
      var closing = pair[1];
      while (url.charAt(url.length - 1) === closing) {
        var openings = url.split(opening).length - 1;
        var closings = url.split(closing).length - 1;
        if (closings <= openings) break;
        suffix = closing + suffix;
        url = url.slice(0, -1);
      }
    });

    return { url: url, suffix: suffix };
  }

  function isEscaped(text, index) {
    var backslashCount = 0;
    var cursor = index - 1;
    while (cursor >= 0 && text.charAt(cursor) === "\\") {
      backslashCount += 1;
      cursor -= 1;
    }
    return backslashCount % 2 === 1;
  }

  function findClosingDelimiter(text, startIndex, openDelimiter, closeDelimiter) {
    var cursor = startIndex + openDelimiter.length;
    while (cursor < text.length) {
      if (
        text.slice(cursor, cursor + closeDelimiter.length) === closeDelimiter &&
        !isEscaped(text, cursor)
      ) {
        return cursor;
      }
      cursor += 1;
    }
    return -1;
  }

  function protectCodeSegments(source, context) {
    var opening = /^[ \t>]*(?:(?:[-+*]|[0-9]+[.)])[ \t]+)?(`{3,}|~{3,})[^\n]*(?:\n|$)|(?<![\\`])(`+)(?!`)/gm;
    var output = "";
    var cursor = 0;
    var match;
    while ((match = opening.exec(source))) {
      var fence = !!match[1];
      var delimiter = match[1] || match[2];
      var closing = new RegExp(fence
        ? "^[ \\t>]*" + delimiter.charAt(0) + "{" + delimiter.length + ",}[ \\t]*(?=\\n|$)"
        : "(?<!`)" + delimiter + "(?!`)", "gm");
      closing.lastIndex = opening.lastIndex;
      var end = closing.exec(source);
      if (!fence && !end) continue;
      var upper = end ? closing.lastIndex : source.length;
      var content = source.slice(opening.lastIndex, end ? end.index : upper);
      var html;
      var prefix = "";
      if (fence) {
        prefix = match[0].slice(0, match[0].indexOf(delimiter));
        var language = match[0].slice(prefix.length + delimiter.length).trim();
        var indent = prefix.match(/^[ \t]*/)[0].length;
        var quoteDepth = prefix.split(">").length - 1;
        if (quoteDepth) content = content.replace(new RegExp("^[ \\t]*(?:>[ \\t]?){" + quoteDepth + "}", "gm"), "");
        content = content.replace(new RegExp("^[ \\t]{0," + indent + "}", "gm"), "");
        html = '<div class="yamabiko-code-block"><button type="button" class="yamabiko-copy-button">' +
          copyButtonLabel + '</button><pre><code' + (language ? ' class="language-' + escapeAttr(language) + '"' : '') +
          '>' + escapeHtml(content) + '</code></pre></div>';
      } else {
        content = content.replace(/\n/g, " ");
        if (/^ .* $/.test(content) && /[^ ]/.test(content)) content = content.slice(1, -1);
        html = '<code>' + escapeHtml(content) + '</code>';
      }
      var key = "@@YBPROTECTED" + context.tokens.length + "@@";
      context.tokens.push({ html: html, block: fence });
      output += source.slice(cursor, match.index) + prefix + key;
      cursor = upper;
      opening.lastIndex = upper;
    }
    return output + source.slice(cursor);
  }

  function protectMathSegments(source, context) {
    var output = "";
    var i = 0;
    while (i < source.length) {
      var url = source.slice(i).match(/^https?:\/\/[^\s<>"']+/i);
      if (url) {
        output += url[0];
        i += url[0].length;
        continue;
      }
      var opening = source.slice(i, i + 2);
      var closing = opening === "\\[" ? "\\]" : opening === "\\(" ? "\\)" : "$$";
      var display = opening === "$$" || opening === "\\[";
      var length = 2;
      var end = -1;
      if ((display || opening === "\\(") && !isEscaped(source, i)) {
        end = findClosingDelimiter(source, i, opening, closing);
      } else if (source.charAt(i) === "$" && !isEscaped(source, i) &&
                 source.charAt(i - 1) !== "$" && source.charAt(i + 1) !== "$" &&
                 !/\s/.test(source.charAt(i + 1))) {
        length = 1;
        var candidate = i + 1;
        while (candidate < source.length && source.charAt(candidate) !== "\n") {
          if (source.charAt(candidate) === "$" && !isEscaped(source, candidate)) {
            if (candidate > i + 1 && !/\s/.test(source.charAt(candidate - 1)) &&
                !/[A-Za-z0-9$]/.test(source.charAt(candidate + 1)) && source.charAt(candidate - 1) !== "$") {
              end = candidate;
            }
            break;
          }
          candidate += 1;
        }
      }
      if (end !== -1) {
        var equation = source.slice(i, end + length);
        // Quote prefixes belong to Markdown. Let the recursive quote parser
        // remove them before protecting the complete equation.
        var linePrefix = source.slice(source.lastIndexOf("\n", i - 1) + 1, i);
        var quoted = /^[ \t]*>/.test(linePrefix) && /\n[ \t]*>/.test(equation);
        if (!quoted && !/@@YBPROTECTED\d+@@/.test(equation)) {
          var key = "@@YBPROTECTED" + context.tokens.length + "@@";
          var classes = "yamabiko-math" + (display ? " yamabiko-math-display" : "");
          context.tokens.push({ html: '<span class="' + classes + '">' + escapeHtml(equation) + '</span>', block: false });
          output += key;
          i = end + length;
          continue;
        }
      }
      output += source.charAt(i);
      i += 1;
    }
    return output;
  }

  function applyInlineMarkdown(text) {
    var input = text;
    if (!input) return "";

    var inlineBreakTokens = [];
    input = input.replace(/<br\s*\/?>/gi, function() {
      var key = "@@YBBR" + inlineBreakTokens.length + "@@";
      inlineBreakTokens.push("<br/>");
      return key;
    });

    var escapedTokens = [];
    input = input.replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\]\^_`{|}~\\])/g, function(_, character) {
      var key = "@@YBESCAPED" + escapedTokens.length + "@@";
      escapedTokens.push(escapeHtml(character));
      return key;
    });

    var inlineLinkTokens = [];
    input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, href) {
      var safe = safeHref(href);
      var textLabel = escapeHtml(label || href);
      var key = "@@YBLINK" + inlineLinkTokens.length + "@@";
      if (!safe) {
        inlineLinkTokens.push(textLabel);
      } else {
        inlineLinkTokens.push(externalLinkHtml(safe, textLabel, /↗\s*$/.test(label || "")));
      }
      return key;
    });

    var bareLinkTokens = [];
    input = input.replace(/https?:\/\/[^\s<>"']+/gi, function(rawUrl) {
      var parts = splitTrailingUrlPunctuation(rawUrl);
      var safe = safeHref(parts.url);
      if (!safe) return rawUrl;
      var key = "@@YBBARELINK" + bareLinkTokens.length + "@@";
      var label = escapeHtml(bareUrlLabel(parts.url));
      bareLinkTokens.push(externalLinkHtml(safe, label, false));
      return key + parts.suffix;
    });

    var output = escapeHtml(input);

    output = output.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    output = output.replace(/__([^_]+)__/g, "<strong>$1</strong>");
    output = output.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    output = output.replace(/_([^_\n]+)_/g, "<em>$1</em>");

    output = output.replace(/@@YBLINK(\d+)@@/g, function(_, index) {
      return inlineLinkTokens[Number(index)] || "";
    });

    output = output.replace(/@@YBBARELINK(\d+)@@/g, function(_, index) {
      return bareLinkTokens[Number(index)] || "";
    });

    output = output.replace(/~~([^~\n]+)~~/g, "<s>$1</s>");
    output = output.replace(/@@YBESCAPED(\d+)@@/g, function(_, index) {
      return escapedTokens[Number(index)] || "";
    });
    output = output.replace(/@@YBBR(\d+)@@/g, function(_, index) {
      return inlineBreakTokens[Number(index)] || "";
    });

    return output;
  }

  function isBlank(line) {
    return !line || !line.trim();
  }

  function renderParagraph(lines) {
    var content = lines.join(" ").trim();
    if (!content) return "";
    return "<p>" + applyInlineMarkdown(content) + "</p>";
  }

  function parseList(lines, startIndex, ordered, context) {
    var index = startIndex;
    var items = [];
    var pattern = ordered ? /^(\s*)(\d+)[.)]\s+(.*)$/ : /^(\s*)[-*+]\s+(.*)$/;
    var first = lines[startIndex].match(pattern);
    var baseIndent = first[1].length;
    var start = ordered ? Number(first[2]) : 1;

    while (index < lines.length) {
      var match = lines[index].match(pattern);
      if (!match || match[1].length !== baseIndent) break;
      var content = ordered ? match[3] : match[2];
      var contentIndent = lines[index].length - content.length;
      var itemLines = [content];
      index += 1;
      while (index < lines.length) {
        if (isBlank(lines[index])) {
          var next = index + 1;
          while (next < lines.length && isBlank(lines[next])) next += 1;
          if (next >= lines.length) break;
          var nextIndent = lines[next].match(/^\s*/)[0].length;
          if (nextIndent <= baseIndent) break;
          itemLines.push("");
          index += 1;
          continue;
        }
        var indent = lines[index].match(/^\s*/)[0].length;
        if (indent <= baseIndent) break;
        itemLines.push(lines[index].slice(Math.min(indent, contentIndent)));
        index += 1;
      }
      items.push("<li>" + renderBlocks(itemLines.join("\n"), context) + "</li>");
      var following = index;
      while (following < lines.length && isBlank(lines[following])) following += 1;
      var sibling = following < lines.length && lines[following].match(pattern);
      if (!sibling || sibling[1].length !== baseIndent) break;
      index = following;
    }

    var tag = ordered ? "ol" : "ul";
    return {
      html: "<" + tag + (ordered && start !== 1 ? ' start="' + start + '"' : "") + ">" + items.join("") + "</" + tag + ">",
      nextIndex: index
    };
  }

  function parseBlockquote(lines, startIndex, context) {
    var index = startIndex;
    var quoteLines = [];

    while (index < lines.length) {
      var line = lines[index];
      if (!/^\s*>/.test(line)) break;
      quoteLines.push(line.replace(/^\s*>\s?/, ""));
      index += 1;
    }

    return {
      html: "<blockquote>" + renderBlocks(quoteLines.join("\n"), context) + "</blockquote>",
      nextIndex: index
    };
  }

  function hasUnescapedPipe(text) {
    var value = String(text || "");
    for (var i = 0; i < value.length; i += 1) {
      if (value.charAt(i) === "|" && !isEscaped(value, i)) {
        return true;
      }
    }
    return false;
  }

  function splitTableRow(line) {
    var text = String(line || "").trim();
    if (!text) return [];
    if (text.charAt(0) === "|") text = text.slice(1);
    if (text.charAt(text.length - 1) === "|") text = text.slice(0, -1);

    var cells = [];
    var segmentStart = 0;
    for (var i = 0; i < text.length; i += 1) {
      if (text.charAt(i) === "|" && !isEscaped(text, i)) {
        cells.push(text.slice(segmentStart, i));
        segmentStart = i + 1;
      }
    }
    cells.push(text.slice(segmentStart));

    return cells.map(function(cell) {
      return cell.replace(/\\\|/g, "|").trim();
    });
  }

  function isDelimiterCell(cell) {
    var value = String(cell || "").trim();
    return /^:?-{3,}:?$/.test(value);
  }

  function parseAlignment(cell) {
    var value = String(cell || "").trim();
    if (/^:-{3,}:$/.test(value)) return "center";
    if (/^:-{3,}$/.test(value)) return "left";
    if (/^-{3,}:$/.test(value)) return "right";
    return null;
  }

  function normalizeCells(cells, columnCount) {
    var normalized = [];
    for (var i = 0; i < columnCount; i += 1) {
      normalized.push(String((cells && cells[i]) || "").trim());
    }
    return normalized;
  }

  function renderTableCell(tag, text, alignment) {
    var style = alignment ? ' style="text-align: ' + alignment + ';"' : "";
    return "<" + tag + style + ">" + applyInlineMarkdown(text) + "</" + tag + ">";
  }

  function parseTable(lines, startIndex) {
    if (startIndex + 1 >= lines.length) return null;

    var headerLine = lines[startIndex];
    var delimiterLine = lines[startIndex + 1];
    if (!hasUnescapedPipe(headerLine) || !hasUnescapedPipe(delimiterLine)) return null;

    var headerCells = splitTableRow(headerLine);
    var delimiterCells = splitTableRow(delimiterLine);
    if (!headerCells.length || delimiterCells.length < headerCells.length) return null;
    if (!delimiterCells.slice(0, headerCells.length).every(isDelimiterCell)) return null;

    var columnCount = headerCells.length;
    var alignments = delimiterCells.slice(0, columnCount).map(parseAlignment);
    var normalizedHeader = normalizeCells(headerCells, columnCount);

    var rowHtml = normalizedHeader.map(function(cell, index) {
      return renderTableCell("th", cell, alignments[index]);
    }).join("");

    var rows = [];
    var index = startIndex + 2;
    while (index < lines.length) {
      var line = lines[index];
      if (isBlank(line) || !hasUnescapedPipe(line)) break;
      var cells = splitTableRow(line);
      if (!cells.length) break;
      var normalizedCells = normalizeCells(cells, columnCount);
      rows.push("<tr>" + normalizedCells.map(function(cell, cellIndex) {
        return renderTableCell("td", cell, alignments[cellIndex]);
      }).join("") + "</tr>");
      index += 1;
    }

    return {
      html:
        "<div class=\"yamabiko-table-wrap\">" +
          "<table>" +
            "<thead><tr>" + rowHtml + "</tr></thead>" +
            "<tbody>" + rows.join("") + "</tbody>" +
          "</table>" +
        "</div>",
      nextIndex: index
    };
  }

  function renderBlocks(input, context) {
    var source = String(input || "").replace(/\r\n?/g, "\n");
    source = protectCodeSegments(source, context);
    source = protectMathSegments(source, context);

    var lines = source.split("\n");
    var htmlParts = [];
    var paragraphBuffer = [];

    function flushParagraph() {
      if (!paragraphBuffer.length) return;
      var paragraph = renderParagraph(paragraphBuffer);
      if (paragraph) htmlParts.push(paragraph);
      paragraphBuffer = [];
    }

    var i = 0;
    while (i < lines.length) {
      var line = lines[i];
      var trimmed = line.trim();

      if (isBlank(line)) {
        flushParagraph();
        i += 1;
        continue;
      }

      var protectedBlock = trimmed.match(/^@@YBPROTECTED(\d+)@@$/);
      if (protectedBlock && context.tokens[Number(protectedBlock[1])] && context.tokens[Number(protectedBlock[1])].block) {
        flushParagraph();
        htmlParts.push(trimmed);
        i += 1;
        continue;
      }

      var heading = line.match(/^(#{1,6})\s+(.*)$/);
      if (heading) {
        flushParagraph();
        var level = heading[1].length;
        htmlParts.push("<h" + level + ">" + applyInlineMarkdown(heading[2].trim()) + "</h" + level + ">");
        i += 1;
        continue;
      }

      if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
        flushParagraph();
        htmlParts.push("<hr/>");
        i += 1;
        continue;
      }

      if (/^\s*>/.test(line)) {
        flushParagraph();
        var quote = parseBlockquote(lines, i, context);
        htmlParts.push(quote.html);
        i = quote.nextIndex;
        continue;
      }

      var parsedTable = parseTable(lines, i);
      if (parsedTable) {
        flushParagraph();
        htmlParts.push(parsedTable.html);
        i = parsedTable.nextIndex;
        continue;
      }

      if (/^\s*[-*+]\s+/.test(line)) {
        flushParagraph();
        var unordered = parseList(lines, i, false, context);
        htmlParts.push(unordered.html);
        i = unordered.nextIndex;
        continue;
      }

      if (/^\s*\d+\.\s+/.test(line)) {
        flushParagraph();
        var ordered = parseList(lines, i, true, context);
        htmlParts.push(ordered.html);
        i = ordered.nextIndex;
        continue;
      }

      paragraphBuffer.push(line.trim());
      i += 1;
    }

    flushParagraph();

    return htmlParts.join("\n");
  }

  global.yamabikoRenderMarkdown = function(markdown) {
    var context = { tokens: [] };
    var html = renderBlocks(markdown, context);
    return html.replace(/@@YBPROTECTED(\d+)@@/g, function(match, index) {
      var token = context.tokens[Number(index)];
      return token ? token.html : match;
    });
  };
})(window);
