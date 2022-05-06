import * as Vue from "https://cdn.jsdelivr.net/npm/vue@3.2.26/dist/vue.esm-browser.prod.js";

export function init(ctx, info) {
  ctx.importCSS("main.css");
  ctx.importCSS("https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap");

  const app = Vue.createApp({
    template: `
    <div class="app">
      <!-- Info Messages -->
      <div id="info-box" class="info-box" v-if="missingDep">
        <p>To successfully build charts, you need to add the following dependency:</p>
        <span>{{ missingDep }}</span>
      </div>
      <form @change="handleFieldChange">
        <div class="container">
          <div class="row header">
            <BaseSelect
              name="type"
              label=" Connect to "
              v-model="fields.type"
              selectClass="input input--xs"
              :inline
              :options="availableDatabases"
              :required
            />

            <BaseInput
              name="variable"
              label=" Assign to "
              type="text"
              placeholder="Assign to"
              v-model="fields.variable"
              inputClass="input input--xs input-text"
              :inline
              :required
            />
          </div>

          <div v-if="fields.type === 'sqlite'" class="row">
            <BaseInput
              name="database_path"
              label="Database Path"
              type="text"
              placeholder="Database Path"
              v-model="fields.database_path"
              inputClass="input"
              :grow
            />
          </div>
          <div v-else>
            <div class="row mixed-row">
              <BaseInput
                name="hostname"
                label="Hostname"
                type="text"
                placeholder="Hostname"
                v-model="fields.hostname"
                inputClass="input"
                :grow
              />
              <BaseInput
                name="port"
                label="Port"
                type="number"
                placeholder="Port"
                v-model="fields.port"
                inputClass="input input--xs input--number"
                :grow
              />
              <BaseInput
                name="database"
                label="Database"
                type="text"
                placeholder="Database"
                v-model="fields.database"
                inputClass="input"
                :grow
              />
            </div>
            <div class="row">
              <BaseInput
                name="username"
                label="User"
                type="text"
                placeholder="User"
                v-model="fields.username"
                inputClass="input"
                :grow
              />
              <BaseInput
                name="password"
                label="Password"
                type="password"
                placeholder="Password"
                v-model="fields.password"
                inputClass="input"
                :grow
              />
            </div>
          </div>
        </div>
      </form>
    </div>
    `,

    data() {
      return {
        fields: info.fields,
        missingDep: info.missing_dep,
        availableDatabases: [
          {label: "PostgreSQL", value: "postgres"},
          {label: "MySQL", value: "mysql"},
          {label: "SQLite", value: "sqlite"}
        ]
      }
    },

    methods: {
      handleFieldChange(event) {
        const { name, value } = event.target;
        ctx.pushEvent("update_field", { field: name, value });
      },
    },

    components: {
      BaseInput: {
        props: {
          label: {
            type: String,
            default: ''
          },
          inputClass: {
            type: String,
            default: 'input'
          },
          modelValue: {
            type: [String, Number],
            default: ''
          },
          inline: {
            type: Boolean,
            default: false
          },
          grow: {
            type: Boolean,
            default: false
          },
          number: {
            type: Boolean,
            default: false
          }
        },

        template: `
        <div v-bind:class="[inline ? 'inline-field' : 'field', grow ? 'grow' : '']">
          <label v-bind:class="inline ? 'inline-input-label' : 'input-label'">
            {{ label }}
          </label>
          <input
            :value="modelValue"
            @input="$emit('update:data', $event.target.value)"
            v-bind="$attrs"
            v-bind:class="[inputClass, number ? 'input-number' : '']"
          >
        </div>
        `
      },

      BaseSelect: {
        props: {
          label: {
            type: String,
            default: ''
          },
          selectClass: {
            type: String,
            default: 'input'
          },
          modelValue: {
            type: String,
            default: ''
          },
          options: {
            type: Array,
            default: [],
            required: true
          },
          required: {
            type: Boolean,
            default: false
          },
          inline: {
            type: Boolean,
            default: false
          }
        },

        template: `
        <div v-bind:class="inline ? 'inline-field' : 'field'">
          <label v-bind:class="inline ? 'inline-input-label' : 'input-label'">
            {{ label }}
          </label>
          <select
            :value="modelValue"
            v-bind="$attrs"
            @change="$emit('update:data', $event.target.value)"
            v-bind:class="selectClass"
          >
            <option
              v-for="option in options"
              :value="option.value"
              :key="option"
              :selected="option.value === modelValue"
            >{{ option.label }}</option>
          </select>
        </div>
        `
      },
    }
  }).mount(ctx.root);

  ctx.handleEvent("update", ({ fields }) => {
    setValues(fields);
  });

  ctx.handleEvent("missing_dep", ({ dep }) => {
    app.missingDep = dep;
  });

  ctx.handleSync(() => {
    // Synchronously invokes change listeners
    document.activeElement &&
      document.activeElement.dispatchEvent(new Event("change", { bubbles: true }));
  });

  function setValues(fields) {
    for (const field in fields) {
      app.fields[field] = fields[field];
    }
  }
}
