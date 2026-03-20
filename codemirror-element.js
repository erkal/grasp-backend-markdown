// CM6 custom element — editor with decorations and scrollTo support.

class CodeMirrorElement extends HTMLElement {
  constructor() {
    super();
    this.view = null;
    this.isUpdating = false;
  }

  connectedCallback() {
    this.innerHTML = '';

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
          this.view.dispatch({
            changes: { from: 0, to: this.view.state.doc.length, insert: newValue || '' }
          });
          this.isUpdating = false;
        }
        break;

      case 'show-line-numbers':
        this.updateLineNumbers();
        break;
    }
  }

  set decorations(ranges) {
    if (!this.view) return;
    const { Decoration, addMarks, clearMarks } = window.CodeMirror6;

    const marks = ranges.map(r =>
      Decoration.mark({ class: r.class }).range(r.from, r.to)
    );

    this.view.dispatch({
      effects: [clearMarks.of(null), addMarks.of(marks)]
    });
  }

  set scrollTo(pos) {
    if (!this.view || pos == null) return;
    const { EditorView } = window.CodeMirror6;
    const offset = typeof pos === 'number' ? pos : pos.offset;
    if (offset == null) return;
    this.view.dispatch({
      selection: { anchor: offset },
      effects: EditorView.scrollIntoView(offset, { y: 'center' })
    });
    this.view.focus();
  }

  updateLineNumbers() {
    if (!this.view) return;
    const { lineNumbersCompartment, lineNumbers } = window.CodeMirror6;
    const show = this.getAttribute('show-line-numbers') !== 'false';
    this.view.dispatch({
      effects: lineNumbersCompartment.reconfigure(show ? lineNumbers() : [])
    });
  }

  focus() {
    if (this.view) {
      this.view.focus();
    }
  }
}

customElements.define('codemirror-element', CodeMirrorElement);
