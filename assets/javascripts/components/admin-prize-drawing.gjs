import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

const ADMIN_BASE = "/admin/plugins/discourse-daily-challenge";

export default class AdminPrizeDrawing extends Component {
  @tracked minCheckIns = 1;
  @tracked startDate = "";
  @tracked endDate = "";
  @tracked results = null;
  @tracked loading = false;

  get apiBase() {
    return this.args.apiBase ?? ADMIN_BASE;
  }

  @action
  updateMinCheckIns(event) {
    this.minCheckIns = Math.max(1, parseInt(event.target.value, 10) || 1);
  }

  @action
  updateStartDate(event) {
    this.startDate = event.target.value;
  }

  @action
  updateEndDate(event) {
    this.endDate = event.target.value;
  }

  @action
  async generateList() {
    this.loading = true;
    this.results = null;

    const data = { min_checkins: this.minCheckIns };
    if (this.startDate) {
      data.start_date = this.startDate;
    }
    if (this.endDate) {
      data.end_date = this.endDate;
    }

    try {
      const response = await ajax(
        `${this.apiBase}/challenges/${this.args.challenge.id}/drawing`,
        { data }
      );

      const lines = response.usernames.map((u) => `@${u}`);
      const countText = i18n("daily_challenge.admin.drawing.eligible_count", {
        count: response.count,
      });
      this.results = response.count > 0 ? `${lines.join("\n")}\n\n${countText}` : countText;
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  @action
  selectAll(event) {
    event.target.select();
  }

  <template>
    <section class="daily-challenge-admin__drawing-section">
      <h3>{{i18n "daily_challenge.admin.drawing.title"}}</h3>

      <div class="daily-challenge-admin__drawing-filters">
        <label class="daily-challenge-admin__drawing-field">
          <span>{{i18n "daily_challenge.admin.drawing.min_checkins"}}</span>
          <input
            type="number"
            min="1"
            value={{this.minCheckIns}}
            class="daily-challenge-admin__drawing-input"
            {{on "input" this.updateMinCheckIns}}
          />
        </label>

        <label class="daily-challenge-admin__drawing-field">
          <span>{{i18n "daily_challenge.admin.drawing.start_date"}}</span>
          <input
            type="date"
            value={{this.startDate}}
            class="daily-challenge-admin__drawing-input"
            {{on "input" this.updateStartDate}}
          />
        </label>

        <label class="daily-challenge-admin__drawing-field">
          <span>{{i18n "daily_challenge.admin.drawing.end_date"}}</span>
          <input
            type="date"
            value={{this.endDate}}
            class="daily-challenge-admin__drawing-input"
            {{on "input" this.updateEndDate}}
          />
        </label>

        <DButton
          @label="daily_challenge.admin.drawing.generate"
          @action={{this.generateList}}
          @isLoading={{this.loading}}
          class="btn-primary"
        />
      </div>

      {{#if this.results}}
        <textarea
          readonly
          rows="12"
          class="daily-challenge-admin__drawing-results"
          {{on "click" this.selectAll}}
        >{{this.results}}</textarea>
      {{/if}}
    </section>
  </template>
}
