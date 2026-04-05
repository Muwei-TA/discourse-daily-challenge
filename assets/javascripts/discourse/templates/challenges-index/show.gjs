import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import AdminChallengePostLeaderboard from "discourse/plugins/discourse-daily-challenge/components/admin-challenge-post-leaderboard";
import AdminCheckInManager from "discourse/plugins/discourse-daily-challenge/components/admin-check-in-manager";
import AdminDailyChallengeForm from "discourse/plugins/discourse-daily-challenge/components/admin-daily-challenge-form";
import AdminPrizeDrawing from "discourse/plugins/discourse-daily-challenge/components/admin-prize-drawing";

const API_BASE = "/challenges";

export default class ChallengesShow extends Component {
  @service router;

  @action
  refreshModel() {
    this.router.refresh();
  }

  <template>
    <div class="container">
      <div class="daily-challenge-admin admin-detail">
        <AdminDailyChallengeForm
          @challenge={{@model}}
          @onSave={{this.refreshModel}}
          @apiBase={{API_BASE}}
          @showRoute="challenges-index.show"
          @indexRoute="challenges-index"
        />
        <AdminChallengePostLeaderboard
          @challenge={{@model}}
          @apiBase={{API_BASE}}
        />
        <AdminCheckInManager
          @challenge={{@model}}
          @apiBase={{API_BASE}}
        />
        <AdminPrizeDrawing
          @challenge={{@model}}
          @apiBase={{API_BASE}}
        />
      </div>
    </div>
  </template>
}
