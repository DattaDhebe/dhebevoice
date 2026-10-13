import 'package:html/dom.dart' as dom;

String readableHtml(dom.Element? element) {
  if (element == null) return '';
  // Extraction must not remove navigation from the crawler's original page.
  final root = element.clone(true);
  root
      .querySelectorAll(
        'script, style, nav, footer, header, aside, form, noscript, iframe, svg, '
        '[hidden], [aria-hidden="true"]',
      )
      .forEach((node) => node.remove());
  const blocks = {
    'p',
    'div',
    'section',
    'article',
    'main',
    'li',
    'blockquote',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'tr',
    'pre',
  };
  final buffer = StringBuffer();
  void visit(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.data.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }
    final tag = node is dom.Element ? node.localName : null;
    if (tag == 'br') buffer.write('\n');
    if (blocks.contains(tag)) buffer.write('\n\n');
    for (final child in node.nodes) {
      visit(child);
    }
    if (blocks.contains(tag)) buffer.write('\n\n');
  }

  visit(root);
  return buffer
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
