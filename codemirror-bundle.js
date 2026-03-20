// CM6 bundle — semantic decoration pipeline + markdown language support.

import { EditorView } from 'codemirror';
import { EditorState, Compartment, StateEffect, StateField } from '@codemirror/state';
import {
  ViewPlugin,
  keymap,
  lineNumbers,
  highlightActiveLineGutter,
  highlightSpecialChars,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
  highlightActiveLine,
  Decoration
} from '@codemirror/view';
import { indentOnInput, bracketMatching } from '@codemirror/language';
import { markdown } from '@codemirror/lang-markdown';
import {
  history, undo, redo,
  cursorCharLeft, cursorCharRight, cursorLineUp, cursorLineDown,
  cursorPageUp, cursorPageDown, cursorLineBoundaryForward, cursorLineBoundaryBackward,
  selectCharLeft, selectCharRight, selectLineUp, selectLineDown,
  selectPageUp, selectPageDown, selectLineBoundaryForward, selectLineBoundaryBackward,
  deleteCharBackward, deleteCharForward,
  insertNewlineAndIndent, insertNewline, insertTab,
  indentLess,
  cursorDocStart, cursorDocEnd, cursorGroupLeft, cursorGroupRight,
  selectDocStart, selectDocEnd, selectGroupLeft, selectGroupRight,
  deleteGroupBackward, deleteGroupForward, deleteToLineStart, deleteToLineEnd,
  selectAll, selectLine, selectParentSyntax, cursorMatchingBracket, simplifySelection,
  addCursorAbove, addCursorBelow,
  moveLineUp, moveLineDown, copyLineUp, copyLineDown, deleteLine,
  indentMore, indentSelection, toggleComment, toggleBlockComment
} from '@codemirror/commands';
import { closeBrackets, closeBracketsKeymap, autocompletion, startCompletion } from '@codemirror/autocomplete';
import {
  search,
  SearchQuery,
  setSearchQuery,
  getSearchQuery,
  findNext,
  findPrevious,
  replaceNext,
  replaceAll,
  openSearchPanel,
  closeSearchPanel,
  highlightSelectionMatches,
  selectNextOccurrence,
  selectMatches,
  selectSelectionMatches,
  gotoLine
} from '@codemirror/search';
import { indentationMarkers } from '@replit/codemirror-indentation-markers';

// Physical keys only — modifier combos handled by Elm
const physicalKeymap = keymap.of([
  { key: "ArrowLeft", run: cursorCharLeft, shift: selectCharLeft },
  { key: "ArrowRight", run: cursorCharRight, shift: selectCharRight },
  { key: "ArrowUp", run: cursorLineUp, shift: selectLineUp },
  { key: "ArrowDown", run: cursorLineDown, shift: selectLineDown },
  { key: "Home", run: cursorLineBoundaryBackward, shift: selectLineBoundaryBackward },
  { key: "End", run: cursorLineBoundaryForward, shift: selectLineBoundaryForward },
  { key: "PageUp", run: cursorPageUp, shift: selectPageUp },
  { key: "PageDown", run: cursorPageDown, shift: selectPageDown },
  { key: "Enter", run: insertNewlineAndIndent },
  { key: "Shift-Enter", run: insertNewline },
  { key: "Backspace", run: deleteCharBackward },
  { key: "Delete", run: deleteCharForward },
  { key: "Tab", run: insertTab },
  { key: "Shift-Tab", run: indentLess },
]);

// Semantic decoration pipeline — Elm sets decoration ranges via element property,
// element dispatches addMarks/clearMarks effects into this StateField.
const addMarks = StateEffect.define();
const clearMarks = StateEffect.define();

const semanticHighlightField = StateField.define({
  create() { return Decoration.none },
  update(value, tr) {
    for (let effect of tr.effects) {
      if (effect.is(clearMarks)) return Decoration.none;
      if (effect.is(addMarks))
        value = value.update({ add: effect.value, sort: true });
    }
    return value.map(tr.changes);
  },
  provide: f => EditorView.decorations.from(f)
});

const lineNumbersCompartment = new Compartment();

const customSetup = [
  lineNumbersCompartment.of(lineNumbers()),
  highlightActiveLineGutter(),
  highlightSpecialChars(),
  history(),
  drawSelection(),
  dropCursor(),
  EditorState.allowMultipleSelections.of(true),
  indentOnInput(),
  bracketMatching(),
  closeBrackets(),
  autocompletion(),
  rectangularSelection(),
  crosshairCursor(),
  highlightActiveLine(),
  highlightSelectionMatches(),
  keymap.of(closeBracketsKeymap),
  physicalKeymap,
  semanticHighlightField,
  markdown(),
  search({
    createPanel: () => ({
      dom: document.createElement("div"),
      top: true
    })
  })
];

window.CodeMirror6 = {
  EditorView,
  EditorState,
  customSetup,
  ViewPlugin,
  keymap,
  SearchQuery,
  setSearchQuery,
  getSearchQuery,
  findNext,
  findPrevious,
  replaceNext,
  replaceAll,
  openSearchPanel,
  closeSearchPanel,
  selectNextOccurrence,
  selectMatches,
  selectSelectionMatches,
  gotoLine,
  indentationMarkers,
  lineNumbersCompartment,
  lineNumbers,
  Decoration,
  addMarks,
  clearMarks,
  cursorDocStart, cursorDocEnd,
  cursorLineBoundaryBackward, cursorLineBoundaryForward,
  cursorGroupLeft, cursorGroupRight,
  cursorPageUp, cursorPageDown,
  selectDocStart, selectDocEnd,
  selectLineBoundaryBackward, selectLineBoundaryForward,
  selectGroupLeft, selectGroupRight,
  deleteGroupBackward, deleteGroupForward, deleteToLineStart, deleteToLineEnd,
  selectAll, selectLine, selectParentSyntax,
  cursorMatchingBracket, simplifySelection,
  addCursorAbove, addCursorBelow,
  undo, redo,
  moveLineUp, moveLineDown, copyLineUp, copyLineDown, deleteLine,
  indentMore, indentLess, indentSelection,
  toggleComment, toggleBlockComment,
  startCompletion
};
