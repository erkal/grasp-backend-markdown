// CM6 custom element — editor with decorations and scrollTo support.

class CodeMirrorElement extends HTMLElement {
  constructor() {
    super();
    this.view = null;
    this.isUpdating = false;
  }

  connectedCallback() {
    this.innerHTML = '';

    if (!window.CodeMirror6) {
      this.innerHTML = '<p style="color: #f48771; padding: 12px; font-family: monospace;">Editor failed to load: CodeMirror bundle not available. Check that build/codemirror-bundle.js loaded.</p>';
      console.error('[codemirror-element] window.CodeMirror6 is not defined.');
      return;
    }

    const { EditorView, EditorState, customSetup, ViewPlugin, keymap } = window.CodeMirror6;

    const changePlugin = ViewPlugin.define((view) => ({
      update: (update) => {
        if (update.docChanged && !this.isUpdating) {
          this.dispatchEvent(new CustomEvent('value-changed', {
            detail: { value: update.state.doc.toString() }
          }));
        }
      }
    }));

    const saveKeymap = keymap.of([{
      key: 'Mod-s',
      run: (view) => {
        this.dispatchEvent(new CustomEvent('save-requested', {
          detail: { value: view.state.doc.toString() }
        }));
        return true;
      }
    }]);

    this.view = new EditorView({
      state: EditorState.create({
        doc: this.getAttribute('value') || '',
        extensions: [
          customSetup,
          saveKeymap,
          changePlugin
        ]
      }),
      parent: this
    });

    this.updateLineNumbers();
  }

  static get observedAttributes() {
    return ['value', 'show-line-numbers'];
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (!this.view) return;

    switch (name) {
      case 'value':
        const currentValue = this.view.state.doc.toString();
        if (newValue !== currentValue) {
          this.isUpdating = true;
          try {
            this.view.dispatch({
              changes: { from: 0, to: this.view.state.doc.length, insert: newValue || '' }
            });
          } finally {
            this.isUpdating = false;
          }
        }
        break;

      case 'show-line-numbers':
        this.updateLineNumbers();
        break;
    }
  }

  set decorations(ranges) {
    if (!this.view || !Array.isArray(ranges)) return;
    const { Decoration, addMarks, clearMarks } = window.CodeMirror6;

    try {
      const docLength = this.view.state.doc.length;
      const marks = ranges
        .filter(r => {
          const valid = r.from >= 0 && r.to >= r.from && r.to <= docLength;
          if (!valid) console.warn('[codemirror-element] Skipping out-of-bounds decoration:', r, 'docLength:', docLength);
          return valid;
        })
        .map(r => Decoration.mark({ class: r.class }).range(r.from, r.to));

      this.view.dispatch({
        effects: [clearMarks.of(null), addMarks.of(marks)]
      });
    } catch (e) {
      console.error('[codemirror-element] Failed to apply decorations:', e);
    }
  }

  set scrollTo(pos) {
    if (!this.view || pos == null) return;
    const { EditorView } = window.CodeMirror6;
    const offset = typeof pos === 'number' ? pos : pos.offset;
    if (offset == null || !Number.isFinite(offset)) return;
    try {
      const docLength = this.view.state.doc.length;
      const clampedOffset = Math.max(0, Math.min(offset, docLength));
      if (clampedOffset !== offset) {
        console.warn('[codemirror-element] scrollTo offset', offset, 'clamped to', clampedOffset, '(docLength:', docLength, ')');
      }
      this.view.dispatch({
        selection: { anchor: clampedOffset },
        effects: EditorView.scrollIntoView(clampedOffset, { y: 'center' })
      });
      this.view.focus();
    } catch (e) {
      console.error('[codemirror-element] Failed to scroll:', e);
    }
  }

  updateLineNumbers() {
    if (!this.view) return;
    try {
      const { lineNumbersCompartment, lineNumbers } = window.CodeMirror6;
      const show = this.getAttribute('show-line-numbers') !== 'false';
      this.view.dispatch({
        effects: lineNumbersCompartment.reconfigure(show ? lineNumbers() : [])
      });
    } catch (e) {
      console.error('[codemirror-element] Failed to update line numbers:', e);
    }
  }

  focus() {
    if (this.view) {
      this.view.focus();
    }
  }
}

customElements.define('codemirror-element', CodeMirrorElement);
