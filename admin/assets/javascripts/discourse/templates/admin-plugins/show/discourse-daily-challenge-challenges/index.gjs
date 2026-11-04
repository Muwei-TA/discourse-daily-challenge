import { fn } from "@ember/helper";
import { LinkTo } from "@ember/routing";
import DBreadcrumbsItem from "discourse/components/d-breadcrumbs-item";
import DButton from "discourse/components/d-button";
import DPageSubheader from "discourse/components/d-page-subheader";
import { i18n } from "discourse-i18n";
import AdminDailyChallengeForm from "discourse/plugins/discourse-daily-challenge/components/admin-daily-challenge-form";

export default <template>
  <DBreadcrumbsItem
    @path="/admin/plugins/discourse-daily-challenge"
    @label={{i18n "daily_challenge.admin.challenges.title"}}
  />

  <div class="daily-challenge-admin admin-detail">
    <DPageSubheader @titleLabel={{i18n "daily_challenge.admin.challenges.title"}}>
      <:actions as |actions|>
        {{#unless @controller.creatingNew}}
          <actions.Primary
            @label="daily_challenge.admin.challenges.new"
            @title="daily_challenge.admin.challenges.new"
            @icon="plus"
            @action={{fn (mut @controller.creatingNew) true}}
            class="daily-challenge-admin__btn-new"
          />
        {{/unless}}
      </:actions>
    </DPageSubheader>

    {{#if @controller.creatingNew}}
      <AdminDailyChallengeForm
        @onSave={{@controller.resetCreatingNew}}
        @onCancel={{@controller.resetCreatingNew}}
        @refreshRoute={{@controller.router.refresh}}
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
                  @route="adminPlugins.show.discourse-daily-challenge-challenges.show"
                  @model={{challenge.id}}
                  class="btn btn-small btn-default"
                >{{i18n "daily_challenge.admin.challenges.edit"}}</LinkTo>
                <DButton
                  @icon="trash-can"
                  @action={{fn @controller.destroyChallenge challenge}}
                  class="btn-small btn-danger"
                  @title="daily_challenge.admin.challenges.delete"
                />
              </td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    {{else}}
      {{#unless @controller.creatingNew}}
        <div class="admin-plugin-config-area__empty-list">
          {{i18n "daily_challenge.admin.challenges.none"}}
          <DButton
            @label="daily_challenge.admin.challenges.cta"
            class="btn-default btn-small"
            @action={{fn (mut @controller.creatingNew) true}}
          />
        </div>
      {{/unless}}
    {{/if}}
  </div>
</template>
