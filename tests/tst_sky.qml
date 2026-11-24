import QtQuick
import QtTest
import "../modules/dashboard/sky.js" as Sky

// The Weather tab's moving backdrop for a WMO weather code (modules/dashboard/sky.js).
TestCase {
    name: "Sky"
    function test_clear_days_shimmer_and_clear_nights_have_stars() {
        compare(Sky.of(0, true).kind, Sky.SUN);
        compare(Sky.of(0, false).kind, Sky.STARS);
    }
    function test_cloud_and_fog_drift() {
        compare(Sky.of(2, true).kind, Sky.CLOUD);
        compare(Sky.of(3, true).kind, Sky.CLOUD);
        compare(Sky.of(45, true).kind, Sky.CLOUD);
        verify(Sky.of(45, true).amount > Sky.of(2, true).amount); // fog is thicker than a few clouds
    }
    function test_drizzle_rain_and_showers_rain_harder_and_harder() {
        compare(Sky.of(51, true).kind, Sky.RAIN);
        verify(Sky.of(51, true).amount < Sky.of(63, true).amount);
        verify(Sky.of(63, true).amount < Sky.of(82, true).amount);
    }
    function test_snow_and_snow_showers() {
        compare(Sky.of(73, true).kind, Sky.SNOW);
        compare(Sky.of(85, true).kind, Sky.SNOW);
    }
    function test_thunderstorms_are_rain_with_flashes() { compare(Sky.of(95, true).kind, Sky.STORM); }
    function test_amounts_stay_between_zero_and_one() {
        for (let c of [0, 1, 2, 3, 45, 48, 51, 55, 61, 65, 71, 75, 80, 82, 85, 86, 95, 99])
            verify(Sky.of(c, true).amount > 0 && Sky.of(c, true).amount <= 1, "code " + c);
    }
}
