import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import AdminChallengePostLeaderboard from "discourse/plugins/discourse-daily-challenge/components/admin-challenge-post-leaderboard";
import AdminCheckInManager from "discourse/plugins/discourse-daily-challenge/components/admin-check-in-manager";
import AdminDailyChallengeForm from "discourse/plugins/discourse-daily-challenge/components/admin-daily-challenge-form";
import AdminPrizeDrawing from "discourse/plugins/discourse-daily-challenge/components/admin-prize-drawing";

export default class ShowDailyChallenge extends Component {
  @service router;

  @action
  refreshModel() {
    this.router.refresh();
  }

  <template>
    <div class="daily-challenge-admin admin-detail">
      <AdminDailyChallengeForm
        @challenge={{@model}}
        @onSave={{this.refreshModel}}
      />
      <AdminChallengePostLeaderboard @challenge={{@model}} />
      <AdminCheckInManager @challenge={{@model}} />
      <AdminPrizeDrawing @challenge={{@model}} />
    </div>
  </template>
}
