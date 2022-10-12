import * as Vue from "https://cdn.jsdelivr.net/npm/vue@3.2.26/dist/vue.esm-browser.prod.js";

export function init(ctx, info) {
  ctx.importCSS("main.css");
  ctx.importCSS(
    "https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap"
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
      grow: {
        type: Boolean,
        default: false,
      },
    },

    methods: {
      available(value, options) {
        return value
          ? options.map((option) => option.value).includes(value)
          : true;
      },
    },

    template: `
    <div v-bind:class="[inline ? 'inline-field' : 'field', grow ? 'grow' : '']">
      <label v-bind:class="inline ? 'inline-input-label' : 'input-label'">
        {{ label }}
      </label>
      <select
        :value="modelValue"
        v-bind="$attrs"
        @change="$emit('update:modelValue', $event.target.value)"
        v-bind:class="[selectClass, { unavailable: !available(modelValue, options) }]"
      >
        <option v-if="!required && !available(modelValue, options)"></option>
        <option
          v-for="option in options"
          :value="option.value"
          :key="option"
          :selected="option.value === modelValue"
        >{{ option.label }}</option>
        <option
          v-if="!available(modelValue, options)"
          class="unavailable"
          :value="modelValue"
        >{{ modelValue }}</option>
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

    computed: {
      emptyClass() {
        if (this.modelValue === "") {
          return "empty";
        }
      },
    },

    template: `
    <div v-bind:class="[inline ? 'inline-field' : 'field', grow ? 'grow' : '']">
      <label v-bind:class="inline ? 'inline-input-label' : 'input-label'">
        {{ label }}
      </label>
      <input
        :value="modelValue"
        @input="$emit('update:modelValue', $event.target.value)"
        v-bind="$attrs"
        v-bind:class="[inputClass, number ? 'input-number' : '', emptyClass]"
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

  const BaseSecret = {
    name: "BaseSecret",

    components: {
      BaseInput: BaseInput,
      BaseSelect: BaseSelect,
    },

    props: {
      textInputName: {
        type: String,
        default: "",
      },
      secretInputName: {
        type: String,
        default: "",
      },
      toggleInputName: {
        type: String,
        default: "",
      },
      label: {
        type: String,
        default: "",
      },
      toggleInputValue: {
        type: [String, Number],
        default: "",
      },
      secretInputValue: {
        type: [String, Number],
        default: "",
      },
      textInputValue: {
        type: [String, Number],
        default: "",
      },
      modalTitle: {
        type: String,
        default: "Select secret",
      },
    },

    methods: {
      selectSecret() {
        const preselectName = this.secretInputValue;
        ctx.selectSecret(
          (secretName) => {
            ctx.pushEvent("update_field", {
              field: this.secretInputName,
              value: secretName,
            });
          },
          preselectName,
          { title: this.modalTitle }
        );
      },
    },

    template: `
      <div class="input-icon-container grow">
        <BaseInput
          v-if="toggleInputValue"
          :name="secretInputName"
          :label="label"
          :value="secretInputValue"
          inputClass="input input-icon"
          :grow
          readonly
          @click="selectSecret"
          @input="$emit('update:secretInputValue', $event.target.value)"
        />
        <BaseInput
          v-else
          :name="textInputName"
          :label="label"
          type="text"
          :value="textInputValue"
          inputClass="input input-icon-text"
          :grow
          @input="$emit('update:textInputValue', $event.target.value)"
        />
        <div class="icon-container">
          <label class="hidden-checkbox">
            <input
              type="checkbox"
              :name="toggleInputName"
              :checked="toggleInputValue"
              @input="$emit('update:toggleInputValue', $event.target.checked)"
              class="hidden-checkbox-input"
            />
            <svg v-if="toggleInputValue" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
                  width="22" height="22">
              <path fill="none" d="M0 0h24v24H0z"/>
              <path d="M18 8h2a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1h2V7a6 6 0 1 1 12 0v1zM5
                10v10h14V10H5zm6 4h2v2h-2v-2zm-4 0h2v2H7v-2zm8 0h2v2h-2v-2zm1-6V7a4 4 0 1 0-8 0v1h8z" fill="#000"/>
            </svg>
            <svg v-else xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
              <path fill="none" d="M0 0h24v24H0z"/>
              <path d="M21 3v18H3V3h18zm-8.001 3h-2L6.6 17h2.154l1.199-3h4.09l1.201 3h2.155l-4.4-11zm-1 2.885L13.244
                12h-2.492l1.247-3.115z" fill="#445668"/>
            </svg>
          </label>
        </div>
      </div>
    `,
  };

  const SQLiteForm = {
    name: "SQLiteForm",

    components: {
      BaseInput: BaseInput,
    },

    props: {
      fields: {
        type: Object,
        default: {},
      },
    },

    template: `
    <div class="row">
      <BaseInput
        name="database_path"
        label="Database Path"
        type="text"
        v-model="fields.database_path"
        inputClass="input"
        :grow
        :required
      />
    </div>
    `,
  };

  const DefaultSQLForm = {
    name: "DefaultSQLForm",

    components: {
      BaseInput: BaseInput,
      BaseSwitch: BaseSwitch,
      BaseSelect: BaseSelect,
      BaseSecret: BaseSecret,
    },

    data() {
      return {
        locked: false,
      };
    },

    props: {
      fields: {
        type: Object,
        default: {},
      },
    },

    template: `
    <div class="row mixed-row">
      <BaseInput
        name="hostname"
        label="Hostname"
        type="text"
        v-model="fields.hostname"
        inputClass="input"
        :grow
        :required
      />
      <BaseInput
        name="port"
        label="Port"
        type="number"
        v-model="fields.port"
        inputClass="input input--xs input--number"
        :grow
        :required
      />
      <BaseSwitch
        name="use_ipv6"
        label="IPv6"
        v-model="fields.use_ipv6"
      />
    </div>
    <div class="row">
      <BaseInput
        name="database"
        label="Database"
        type="text"
        v-model="fields.database"
        inputClass="input"
        :grow
      />
      <BaseInput
        name="username"
        label="User"
        type="text"
        v-model="fields.username"
        inputClass="input"
        :grow
      />
      <BaseSecret
        textInputName="password"
        secretInputName="password_secret"
        toggleInputName="use_password_secret"
        label="Password"
        v-model:textInputValue="fields.password"
        v-model:secretInputValue="fields.password_secret"
        v-model:toggleInputValue="fields.use_password_secret"
        modalTitle="Set password"
      />
    </div>
    `,
  };

  const AthenaForm = {
    name: "AthenaForm",

    components: {
      BaseInput: BaseInput,
      BaseSecret: BaseSecret,
    },

    props: {
      fields: {
        type: Object,
        default: {},
      },
      helpBox: {
        type: String,
        default: "",
      },
      hasAwsCredentials: {
        type: Boolean,
        default: false,
      },
    },

    methods: {
      areFieldsEmpty(currentField, otherField) {
        if (currentField === "" && otherField === "") {
          return true;
        }

        return false;
      },
    },

    template: `
    <div class="row mixed-row">
      <BaseInput
        name="access_key_id"
        label="Access Key ID"
        type="text"
        v-model="fields.access_key_id"
        inputClass="input"
        :grow
        :required="!hasAwsCredentials"
      />
      <BaseSecret
        textInputName="secret_access_key"
        secretInputName="secret_access_key_secret"
        toggleInputName="use_secret_access_key_secret"
        label="Secret Access Key"
        v-model:textInputValue="fields.secret_access_key"
        v-model:secretInputValue="fields.secret_access_key_secret"
        v-model:toggleInputValue="fields.use_secret_access_key_secret"
        modalTitle="Set secret access key"
      />
    </div>
    <div class="row mixed-row">
      <BaseInput
        name="token"
        label="Session Token"
        type="password"
        v-model="fields.token"
        inputClass="input"
        :grow
      />
      <BaseInput
        name="region"
        label="Region"
        type="text"
        v-model="fields.region"
        inputClass="input"
        :grow
        :required="!hasAwsCredentials"
      />
    </div>
    <div class="row mixed-row">
      <BaseInput
        name="database"
        label="Database"
        type="text"
        v-model="fields.database"
        inputClass="input"
        :grow
        :required
      />
      <BaseInput
        name="workgroup"
        label="Workgroup"
        type="text"
        v-model="fields.workgroup"
        inputClass="input"
        :grow
        :required="!!areFieldsEmpty(fields.workgroup, fields.output_location)"
      />
      <BaseInput
        name="output_location"
        label="Output Location"
        type="url"
        v-model="fields.output_location"
        inputClass="input"
        :grow
        :required="!!areFieldsEmpty(fields.output_location, fields.workgroup)"
      />
    </div>
    <small class="help-box" v-if="hasAwsCredentials" v-html="helpBox" />
    `,
  };

  const BigQueryForm = {
    name: "BigQueryForm",

    components: {
      BaseInput: BaseInput,
    },

    props: {
      fields: {
        type: Object,
        default: {},
      },
      helpBox: {
        type: String,
        default: "",
      },
    },

    methods: {
      credentialsChange(_) {
        this.updateCredentials(this.$refs.credentials.files);
      },

      credentialsClick(_) {
        this.$refs.credentials.click();
      },

      dragOver(event) {
        event.preventDefault();
      },

      dragLeave(_) {},

      drop(event) {
        event.preventDefault();
        this.updateCredentials(event.dataTransfer.files);
      },

      updateCredentials(fileList) {
        const file = fileList[0];

        if (file && file.type === "application/json") {
          const reader = new FileReader();

          reader.onload = (res) => {
            const value = JSON.parse(res.target.result);
            ctx.pushEvent("update_field", { field: "credentials", value });
          };

          reader.readAsText(file);
        }
      },
    },

    template: `
    <div class="row mixed-row">
      <BaseInput
        name="project_id"
        label="Project ID"
        type="text"
        v-model="fields.project_id"
        inputClass="input"
        :grow
        :required
      />
      <BaseInput
        name="default_dataset_id"
        label="Default Dataset ID (Optional)"
        type="text"
        v-model="fields.default_dataset_id"
        inputClass="input"
        :grow
      />
    </div>
    <div class="row">
      <div class="draggable" @dragover="dragOver" @dragleave="dragLeave" @drop="drop" @click="credentialsClick">
        <label for="credentials">
          Drag your credentials JSON file here<br/>
          or click here to select your file.
        </label>
        <input type="file" ref="credentials" @change="credentialsChange" />
      </div>
    </div>
    <small class="help-box" v-html="helpBox" />
    `,
  };

  const app = Vue.createApp({
    components: {
      BaseInput: BaseInput,
      BaseSelect: BaseSelect,
      SQLiteForm: SQLiteForm,
      DefaultSQLForm: DefaultSQLForm,
      BigQueryForm: BigQueryForm,
      AthenaForm: AthenaForm,
    },

    template: `
    <div class="app">
      <!-- Info Messages -->
      <div id="info-box" class="info-box" v-if="missingDep">
        <p>To successfully connect, you need to add the following dependency:</p>
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
            />

            <BaseInput
              name="variable"
              label=" Assign to "
              type="text"
              v-model="fields.variable"
              inputClass="input input--xs input-text"
              :inline
            />
          </div>

          <SQLiteForm v-bind:fields="fields" v-if="isSQLite" />
          <BigQueryForm v-bind:fields="fields" v-bind:helpBox="helpBox" v-if="isBigQuery" />
          <AthenaForm v-bind:fields="fields" v-bind:helpBox="helpBox" v-bind:hasAwsCredentials="hasAwsCredentials" v-if="isAthena" />
          <DefaultSQLForm v-bind:fields="fields" v-if="isDefaultDatabase" />
        </div>
      </form>
    </div>
    `,

    data() {
      return {
        fields: info.fields,
        missingDep: info.missing_dep,
        helpBox: info.help_box,
        hasAwsCredentials: info.has_aws_credentials,
        availableDatabases: [
          { label: "PostgreSQL", value: "postgres" },
          { label: "MySQL", value: "mysql" },
          { label: "SQLite", value: "sqlite" },
          { label: "Google BigQuery", value: "bigquery" },
          { label: "Mongo DB", value: "mongo" },
          { label: "AWS Athena", value: "athena" },
        ],
      };
    },

    computed: {
      isSQLite() {
        return this.fields.type === "sqlite";
      },

      isBigQuery() {
        return this.fields.type === "bigquery";
      },

      isAthena() {
        return this.fields.type === "athena";
      },

      isDefaultDatabase() {
        return ["postgres", "mysql", "mongo"].includes(this.fields.type);
      },
    },

    methods: {
      handleFieldChange(event) {
        const field = event.target.name;
        if (field) {
          const value = this.fields[field];
          ctx.pushEvent("update_field", { field, value });
        }
      },
    },
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
      document.activeElement.dispatchEvent(
        new Event("change", { bubbles: true })
      );
  });

  function setValues(fields) {
    for (const field in fields) {
      app.fields[field] = fields[field];
    }
  }
}
