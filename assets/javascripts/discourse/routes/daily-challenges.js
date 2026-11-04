import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class DailyChallengesRoute extends DiscourseRoute {
  model() {
    return ajax("/daily-challenges.json");
  }
}
