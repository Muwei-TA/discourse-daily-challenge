import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

export default class DailyChallenges extends Component {
  <template>
    <div class="container daily-challenge-activities">
      <h1>{{i18n "daily_challenge.sidebar.title"}}</h1>
      <p>{{i18n "daily_challenge.admin.form.daily_topics_help"}}</p>
      {{#each @model.activities as |activity|}}
        <section class="daily-challenge-activities__activity">
          <h2>{{activity.name}}</h2>
          <p>{{activity.start_date}} – {{activity.end_date}} · <a href={{activity.topics_url}}>{{activity.tag_name}}</a></p>
          {{#if activity.today_topic_url}}
            <p><a class="btn btn-primary" href={{activity.today_topic_url}}>{{i18n "daily_challenge.admin.form.today_topic"}}</a></p>
          {{/if}}
          <details>
            <summary>{{i18n "daily_challenge.admin.form.daily_topic_history"}}</summary>
            <ul>
              {{#each activity.daily_topics as |topic|}}
                <li><a href={{topic.url}}>{{topic.title}}</a></li>
              {{/each}}
            </ul>
          </details>
        </section>
      {{else}}
        <p>{{i18n "daily_challenge.admin.challenges.none"}}</p>
      {{/each}}
    </div>
  </template>
}
