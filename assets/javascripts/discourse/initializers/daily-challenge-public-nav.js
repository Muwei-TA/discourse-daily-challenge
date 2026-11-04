import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Public entry point for challenge topics. Challenge dashboards remain staff-only.
export default {
  name: "daily-challenge-public-nav",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (!siteSettings.daily_challenge_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.addCommunitySectionLink({
        name: "daily-challenge-activities",
        href: "/daily-challenges",
        title: i18n("daily_challenge.sidebar.title"),
        text: i18n("daily_challenge.sidebar.title"),
        icon: "flag",
      });
    });
  },
};
