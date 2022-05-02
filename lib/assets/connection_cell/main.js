export function init(ctx, info) {
  ctx.importCSS("main.css");
  ctx.importCSS("https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap");

  let formHtml = buildSQLForm();

  if (info.fields.type == "sqlite") {
    formHtml = buildSQLiteForm();
  }

  ctx.root.innerHTML = `
    <div class="app">
      <div id="info-box" class="info-box"></div>
      <div class="container">
        <div class="row header">
          <div class="inline-field">
            <label class="inline-input-label"> Connect to </label>
            <select class="input input--xs" name="type">
              <option value="postgres">PostgreSQL</option>
              <option value="mysql">MySQL</option>
              <option value="sqlite">SQLite3</option>
            </select>
          </div>
          <div class="inline-field">
            <label class="inline-input-label"> Assign to </label>
            <input class="input input--xs input--text" name="variable" type="text" />
          </div>
        </div>
        ${formHtml}
      </div>
    </div>
  `;

  updateInfoBox(info.missing_dep);
  setValues(info.fields);

  ctx.root.addEventListener("change", handleFieldChange);

  function handleFieldChange(event) {
    const { name, value } = event.target;
    ctx.pushEvent("update_field", { field: name, value });
  }

  ctx.handleEvent("update", ({ fields }) => {
    setValues(fields);
  });

  ctx.handleEvent("missing_dep", ({ dep }) => {
    updateInfoBox(dep);
  });

  ctx.handleSync(() => {
    // Synchronously invokes change listeners
    document.activeElement &&
      document.activeElement.dispatchEvent(new Event("change", { bubbles: true }));
  });

  function setValues(fields) {
    for (const field in fields) {
      const input = ctx.root.querySelector(`[name="${field}"]`);

      if (input)
        input.value = fields[field];
    }
  }

  function updateInfoBox(dep) {
    const infoBox = ctx.root.querySelector("#info-box");

    if (dep) {
      infoBox.classList.remove("hidden");
      infoBox.innerHTML = `<p>To successfully connect, you need to add the following dependency:</p><span>${dep}</span>`;
    } else {
      infoBox.classList.add("hidden");
    }
  }

  function buildSQLiteForm() {
    return `
    <div class="row mixed-row">
      <div class="field grow">
        <label class="input-label">Path</label>
        <input class="input" name="path" type="text" />
      </div>
    </div>
    `;
  }

  function buildSQLForm() {
    return `
    <div class="row mixed-row">
      <div class="field grow">
        <label class="input-label">Hostname</label>
        <input class="input" name="hostname" type="text" />
      </div>
      <div class="field">
        <label class="input-label">Port</label>
        <input class="input input--xs input--number" name="port" type="number" />
      </div>
      <div class="field grow">
        <label class="input-label">Database</label>
        <input class="input" name="database" type="text" />
      </div>
    </div>
    <div class="row">
      <div class="field grow">
        <label class="input-label">User</label>
        <input class="input" name="username" type="text" />
      </div>
      <div class="field grow">
        <label class="input-label">Password</label>
        <input class="input" name="password" type="password" />
      </div>
    </div>
    `;
  }
}
