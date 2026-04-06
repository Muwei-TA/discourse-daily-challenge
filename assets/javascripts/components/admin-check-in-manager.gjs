import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import AdminCheckInForm from "discourse/plugins/discourse-daily-challenge/components/admin-check-in-form";

const ADMIN_BASE = "/admin/plugins/discourse-daily-challenge";
const PAGE_SIZE = 25;

export default class AdminCheckInManager extends Component {
  @service toasts;
  @service dialog;

  @tracked addingCheckIn = false;
  @tracked checkIns = this.args.challenge?.check_ins ?? [];
  @tracked currentPage = 0;

  get apiBase() {
    return this.args.apiBase ?? ADMIN_BASE;
  }

  get totalPages() {
    return Math.ceil(this.checkIns.length / PAGE_SIZE);
  }

  get pagedCheckIns() {
    const start = this.currentPage * PAGE_SIZE;
    return this.checkIns.slice(start, start + PAGE_SIZE);
  }

  get showingFrom() {
    return this.checkIns.length === 0 ? 0 : this.currentPage * PAGE_SIZE + 1;
  }

  get showingTo() {
    return Math.min((this.currentPage + 1) * PAGE_SIZE, this.checkIns.length);
  }

  get hasPreviousPage() {
    return this.currentPage > 0;
  }

  get hasNextPage() {
    return this.currentPage < this.totalPages - 1;
  }

  get showPagination() {
    return this.totalPages > 1;
  }

  get previousDisabled() {
    return !this.hasPreviousPage;
  }

  get nextDisabled() {
    return !this.hasNextPage;
  }

  @action
  showAddForm() {
    this.addingCheckIn = true;
  }

  @action
  cancelAddForm() {
    this.addingCheckIn = false;
  }

  @action
  onCheckInAdded(checkIn) {
    this.addingCheckIn = false;
    this.checkIns = [checkIn, ...this.checkIns];
    this.currentPage = 0;
  }

  @action
  previousPage() {
    if (this.hasPreviousPage) {
      this.currentPage = this.currentPage - 1;
    }
  }

  @action
  nextPage() {
    if (this.hasNextPage) {
      this.currentPage = this.currentPage + 1;
    }
  }

  @action
  removeCheckIn(checkIn) {
    this.dialog.deleteConfirm({
      message: i18n("daily_challenge.admin.check_ins.confirm_remove"),
      didConfirm: () => {
        return ajax(
          `${this.apiBase}/challenges/${this.args.challenge.id}/check_ins/${checkIn.id}`,
          { type: "DELETE" }
        )
          .then(() => {
            this.toasts.success({
              duration: "short",
              data: {
                message: i18n("daily_challenge.admin.check_ins.removed"),
              },
            });
            this.checkIns = this.checkIns.filter((c) => c.id !== checkIn.id);
            if (this.currentPage >= this.totalPages) {
              this.currentPage = Math.max(0, this.totalPages - 1);
            }
          })
          .catch(popupAjaxError);
      },
    });
  }

  <template>
    <section class="daily-challenge-admin__check-ins-section">
      <div class="daily-challenge-admin__check-ins-header">
        <h3>{{i18n "daily_challenge.admin.check_ins.title"}}</h3>
        {{#unless this.addingCheckIn}}
          <DButton
            @label="daily_challenge.admin.check_ins.add"
            @icon="plus"
            class="btn-default btn-small"
            @action={{this.showAddForm}}
          />
        {{/unless}}
      </div>

      {{#if this.addingCheckIn}}
        <AdminCheckInForm
          @challengeId={{@challenge.id}}
          @apiBase={{this.apiBase}}
          @onSave={{this.onCheckInAdded}}
          @onCancel={{this.cancelAddForm}}
        />
      {{/if}}

      {{#if this.checkIns.length}}
        <table class="daily-challenge-admin__check-ins-table">
          <thead>
            <tr>
              <th>{{i18n "daily_challenge.admin.check_ins.user"}}</th>
              <th>{{i18n "daily_challenge.admin.check_ins.date"}}</th>
              <th>{{i18n "daily_challenge.admin.check_ins.source"}}</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {{#each this.pagedCheckIns as |checkIn|}}
              <tr>
                <td>@{{checkIn.username}}</td>
                <td>{{checkIn.check_in_date}}</td>
                <td>
                  {{#if checkIn.admin_added}}
                    {{i18n "daily_challenge.admin.check_ins.source_admin"}}
                  {{else}}
                    {{i18n "daily_challenge.admin.check_ins.source_post"}}
                  {{/if}}
                </td>
                <td>
                  <DButton
                    @icon="trash-can"
                    @action={{fn this.removeCheckIn checkIn}}
                    class="btn-small btn-danger"
                    @title="daily_challenge.admin.check_ins.remove"
                  />
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>

        {{#if this.showPagination}}
          <div class="daily-challenge-admin__check-ins-pagination">
            <DButton
              @label="daily_challenge.admin.check_ins.previous"
              @action={{this.previousPage}}
              @disabled={{this.previousDisabled}}
              class="btn-default btn-small"
            />
            <span class="daily-challenge-admin__check-ins-pagination-info">
              {{i18n
                "daily_challenge.admin.check_ins.showing"
                from=this.showingFrom
                to=this.showingTo
                total=this.checkIns.length
              }}
            </span>
            <DButton
              @label="daily_challenge.admin.check_ins.next"
              @action={{this.nextPage}}
              @disabled={{this.nextDisabled}}
              class="btn-default btn-small"
            />
          </div>
        {{/if}}
      {{else}}
        {{#unless this.addingCheckIn}}
          <p class="admin-plugin-config-area__empty-list">
            {{i18n "daily_challenge.admin.check_ins.none"}}
          </p>
        {{/unless}}
      {{/if}}
    </section>
  </template>
}
