import { createApp } from "vue/dist/vue.esm-browser.prod.js";
import "./main.css";

export function init(ctx, payload) {
  ctx.importCSS("main.css");
  ctx.importCSS(
    "https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap"
  );
  ctx.importCSS(
    "https://cdn.jsdelivr.net/npm/remixicon@2.5.0/fonts/remixicon.min.css"
  );

  const BaseSelect = {
    name: "BaseSelect",

    props: {
      label: {
        type: String,
        default: "",
      },
      selectClass: {
        type: String,
        default: "input",
      },
      modelValue: {
        type: String,
        default: "",
      },
      options: {
        type: Array,
        default: [],
        required: true,
      },
      required: {
        type: Boolean,
        default: false,
      },
      inline: {
        type: Boolean,
        default: false,
      },
      existent: {
        type: Boolean,
        default: false,
      },
      disabled: {
        type: Boolean,
        default: false,
      },
    },

    template: `
    <div v-bind:class="inline ? 'inline-field' : 'field'">
      <label v-bind:class="inline ? 'inline-input-label' : 'input-label'">
        {{ label }}
      </label>
      <select
        :value="modelValue"
        v-bind="$attrs"
        v-bind:disabled="disabled"
        @change="$emit('update:modelValue', $event.target.value)"
        v-bind:class="[selectClass, existent ? '' : 'nonexistent']"
      >
        <option
          v-for="option in options"
          :value="option.value"
          :key="option"
          :selected="option.value === modelValue"
        >{{ option.label }}</option>
      </select>
    </div>
    `,
  };

  const BaseInput = {
    name: "BaseInput",

    props: {
      label: {
        type: String,
        default: "",
      },
      inputClass: {
        type: String,
        default: "input",
      },
      modelValue: {
        type: [String, Number],
        default: "",
      },
      inline: {
        type: Boolean,
        default: false,
      },
      grow: {
        type: Boolean,
        default: false,
      },
      number: {
        type: Boolean,
        default: false,
      },
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
    `,
  };

  const BaseSwitch = {
    name: "BaseSwitch",

    props: {
      label: {
        type: String,
        default: "",
      },
      modelValue: {
        type: Boolean,
        default: true,
      },
      inline: {
        type: Boolean,
        default: false,
      },
      grow: {
        type: Boolean,
        default: false,
      },
    },

    template: `
    <div v-bind:class="[inline ? 'inline-field' : 'field', grow ? 'grow' : '']">
      <label v-bind:class="inline ? 'inline-input-label' : 'input-label'">
        {{ label }}
      </label>
      <div class="input-container">
        <label class="switch-button">
          <input
            :checked="modelValue"
            type="checkbox"
            @input="$emit('update:modelValue', $event.target.checked)"
            v-bind="$attrs"
            class="switch-button-checkbox"
            v-bind:class="[inputClass, number ? 'input-number' : '']"
          >
          <div class="switch-button-bg" />
        </label>
      </div>
    </div>
    `,
  };

  const ToggleBox = {
    name: "ToggleBox",

    props: {
      toggle: {
        type: Boolean,
        default: true,
      },
    },

    template: `
    <div v-bind:class="toggle ? 'hidden' : ''">
      <slot></slot>
    </div>
    `,
  };

  const app = createApp({
    components: {
      BaseSelect: BaseSelect,
      BaseInput: BaseInput,
      BaseSwitch: BaseSwitch,
      ToggleBox: ToggleBox,
    },

    template: `
    <div class="app">
      <div>
        <ToggleBox class="info-box" v-bind:toggle="isConnectionExistent">
          <p>To successfully query, you need at least one database connection available.</p>
          <p>To create a database connection, you can add the <span class="strong">Database connection</span> smart cell.</p>
        </ToggleBox>
        <div class="box box-warning" v-if="missingDep">
          <p>To successfully query with {{ connectionType }}, you need to add the following dependency:</p>
          <pre><code>{{ missingDep }}</code></pre>
        </div>
        <div class="header">
          <BaseSelect
            @change="handleConnectionChange"
            name="connection_variable"
            label="Query"
            v-model="(payload.connection || {}).variable"
            selectClass="input input--md"
            :existent="isConnectionExistent"
            :disabled="isConnectionDisabled"
            :inline
            :options="availableConnections"
          />
          <BaseInput
            @change="handleResultVariableChange"
            name="result_variable"
            label="Assign to"
            type="text"
            placeholder="Assign to"
            v-model="payload.result_variable"
            inputClass="input input--xs"
            :inline
          />
          <BaseInput
            v-if="hasTimeout"
            @change="handleTimeoutChange"
            name="timeout"
            label="Timeout (s)"
            type="number"
            v-model="payload.timeout"
            inputClass="input input--xs"
            :inline
          />
          <BaseSwitch
            v-if="hasCache"
            @change="handleCacheQueryChange"
            name="cache_query"
            label="Cache"
            v-model="payload.cache_query"
            :inline
          />
          <div class="grow"></div>
          <button id="help-toggle" @click="toggleHelpBox" class="icon-button">
            <i class="ri ri-questionnaire-line" aria-hidden="true"></i>
          </button>
      </div>
      <ToggleBox id="help-box" class="section help-box" v-bind:toggle="isHelpBoxHidden">
        <span v-pre>To dynamically inject values into the query use double curly braces, like {{name}}.</span>
      </ToggleBox>
    </div>
    `,

    data() {
      return {
        isHelpBoxHidden: true,
        isSettingsBoxHidden: true,
        isConnectionExistent: false,
        isConnectionDisabled: true,
        payload: payload,
        missingDep: payload.missing_dep,
        availableDatabases: {
          postgres: "PostgreSQL",
          mysql: "MySQL",
          sqlite: "SQLite",
          bigquery: "Google BigQuery",
          athena: "AWS Athena",
          snowflake: "Snowflake",
          sqlserver: "SQL Server"
        },
      };
    },

    computed: {
      availableConnections() {
        const connection = this.payload.connection;
        const connections = this.payload.connections;

        const availableConnection =
          connection &&
          connections.some((conn) => conn.variable === connection.variable);

        if (connection === null) {
          this.isConnectionExistent = false;
          this.isConnectionDisabled = true;
          return [];
        } else if (availableConnection) {
          this.isConnectionExistent = true;
          this.isConnectionDisabled = false;
          return this.buildSelectConnectionOptions(connections);
        } else {
          this.isConnectionExistent = false;
          this.isConnectionDisabled = false;
          return this.buildSelectConnectionOptions([
            connection,
            ...connections,
          ]);
        }
      },
      hasCache() {
        return this.payload.connection?.type === 'athena';
      },
      hasTimeout() {
        const hasTimeout = ["postgres", "mysql", "sqlite", "sqlserver"];
        return hasTimeout.includes(this.payload.connection?.type);
      },
      connectionType() {
        return this.payload.connection?.type;
      }
    },

    methods: {
      buildSelectConnectionOptions(connections) {
        return connections.map((conn) => {
          return {
            label: `${conn.variable} (${this.availableDatabases[conn.type]})`,
            value: conn.variable,
          };
        });
      },

      handleResultVariableChange({ target: { value } }) {
        ctx.pushEvent("update_result_variable", value);
      },

      handleCacheQueryChange({ target: { checked } }) {
        ctx.pushEvent("update_cache_query", checked);
      },

      handleTimeoutChange({ target: { value } }) {
        ctx.pushEvent("update_timeout", value);
      },

      handleConnectionChange({ target: { value } }) {
        ctx.pushEvent("update_connection", value);
      },

      toggleHelpBox(_) {
        this.isHelpBoxHidden = !this.isHelpBoxHidden;
      },

      toggleSettingsBox(_) {
        this.isSettingsBoxHidden = !this.isSettingsBoxHidden;
      },
    },
  }).mount(ctx.root);

  ctx.handleEvent("update_result_variable", (variable) => {
    app.payload.result_variable = variable;
  });

  ctx.handleEvent("update_connection", (variable) => {
    const connection = app.payload.connections.find(
      (conn) => conn.variable === variable
    );
    app.payload.connection = connection;
  });

  ctx.handleEvent("update_cache_query", (value) => {
    app.payload.cache_query = value;
  });

  ctx.handleEvent("update_timeout", (timeout) => {
    app.payload.timeout = timeout;
  });

  ctx.handleEvent("connections", ({ connections, connection }) => {
    app.payload.connections = connections;
    app.payload.connection = connection;
  });

  ctx.handleEvent("missing_dep", ({ dep }) => {
    app.missingDep = dep;
  });

  ctx.handleSync(() => {
    // Synchronously invokes change listeners
    document.activeElement &&
      document.activeElement.dispatchEvent(
        new Event("change", { bubbles: true })
      );
  });
}
