import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DPageSubheader from "discourse/components/d-page-subheader";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import AdminDailyChallengeForm from "discourse/plugins/discourse-daily-challenge/components/admin-daily-challenge-form";

const API_BASE = "/challenges";

export default class ChallengesIndexIndex extends Component {
  @service currentUser;
  @service dialog;
  @service toasts;
  @service router;

  @tracked creatingNew = false;

  @action
  showNewForm() {
    this.creatingNew = true;
  }

  @action
  resetCreatingNew() {
    this.creatingNew = false;
  }

  @action
  destroyChallenge(challenge) {
    this.dialog.deleteConfirm({
      message: i18n("daily_challenge.admin.challenges.confirm_delete"),
      didConfirm: () => {
        return ajax(`${API_BASE}/challenges/${challenge.id}`, {
          type: "DELETE",
        })
          .then(() => {
            this.toasts.success({
              duration: "short",
              data: {
                message: i18n("daily_challenge.admin.challenges.deleted"),
              },
            });
            if (
              this.currentUser.is_challenge_manager &&
              !this.currentUser.staff
            ) {
              this.router
                .transitionTo("challenges-index")
                .then(() => this.router.refresh());
            } else {
              this.router.refresh();
            }
          })
          .catch(popupAjaxError);
      },
    });
  }

  <template>
    <div class="container">
      <div class="daily-challenge-admin admin-detail">
        <DPageSubheader
          @titleLabel={{i18n "daily_challenge.admin.challenges.title"}}
        >
          <:actions as |actions|>
            {{#unless this.creatingNew}}
              <actions.Primary
                @label="daily_challenge.admin.challenges.new"
                @title="daily_challenge.admin.challenges.new"
                @icon="plus"
                @action={{this.showNewForm}}
                class="daily-challenge-admin__btn-new"
              />
            {{/unless}}
          </:actions>
        </DPageSubheader>

        {{#if this.creatingNew}}
          <AdminDailyChallengeForm
            @apiBase={{API_BASE}}
            @showRoute="challenges-index.show"
            @indexRoute="challenges-index"
            @onSave={{this.resetCreatingNew}}
            @onCancel={{this.resetCreatingNew}}
          />
        {{/if}}

        {{#if @model.challenges.length}}
          <table class="daily-challenge-admin__table">
            <thead>
              <tr>
                <th>{{i18n "daily_challenge.admin.challenges.name_col"}}</th>
                <th>{{i18n "daily_challenge.admin.challenges.dates_col"}}</th>
                <th>{{i18n "daily_challenge.admin.challenges.participants_col"}}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {{#each @model.challenges as |challenge|}}
                <tr class="daily-challenge-admin__row">
                  <td>
                    <strong>{{challenge.name}}</strong>
                    {{#if challenge.tag_name}}
                      <br /><small>{{challenge.tag_name}}</small>
                    {{/if}}
                  </td>
                  <td>{{challenge.start_date}} – {{challenge.end_date}}</td>
                  <td>{{challenge.participant_count}}</td>
                  <td class="daily-challenge-admin__actions">
                    <LinkTo
                      @route="challenges-index.show"
                      @model={{challenge.id}}
                      class="btn btn-small btn-default"
                    >{{i18n "daily_challenge.admin.challenges.edit"}}</LinkTo>
                    <DButton
                      @icon="trash-can"
                      @action={{fn this.destroyChallenge challenge}}
                      class="btn-small btn-danger"
                      @title="daily_challenge.admin.challenges.delete"
                    />
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        {{else}}
          {{#unless this.creatingNew}}
            <div class="admin-plugin-config-area__empty-list">
              {{i18n "daily_challenge.admin.challenges.none"}}
              <DButton
                @label="daily_challenge.admin.challenges.cta"
                class="btn-default btn-small"
                @action={{this.showNewForm}}
              />
            </div>
          {{/unless}}
        {{/if}}
      </div>
    </div>
  </template>
}
