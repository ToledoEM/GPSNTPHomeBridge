"""The GPS & NTP Home Bridge integration."""

from __future__ import annotations

from pathlib import Path

from homeassistant.components.frontend import add_extra_js_url
from homeassistant.components.http import StaticPathConfig
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant
from homeassistant.loader import async_get_integration

from .const import CONF_HOST, CONF_PORT, DOMAIN, FRONTEND_REGISTERED, STRATEGY_FILE, STRATEGY_URL
from .coordinator import GpsCoordinator, NtpCoordinator

PLATFORMS: list[Platform] = [Platform.SENSOR]


async def _async_register_frontend(hass: HomeAssistant) -> None:
    """Serve the dashboard strategy and load it in the frontend, once."""
    domain_data = hass.data.setdefault(DOMAIN, {})
    if domain_data.get(FRONTEND_REGISTERED):
        return
    domain_data[FRONTEND_REGISTERED] = True

    path = Path(__file__).parent / "frontend" / STRATEGY_FILE
    await hass.http.async_register_static_paths(
        [StaticPathConfig(STRATEGY_URL, str(path), cache_headers=False)]
    )
    # The version in the URL makes browsers refetch after an update.
    integration = await async_get_integration(hass, DOMAIN)
    add_extra_js_url(hass, f"{STRATEGY_URL}?v={integration.version}")


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up from a config entry."""
    host = entry.data[CONF_HOST]
    port = entry.data[CONF_PORT]

    ntp = NtpCoordinator(hass, host, port)
    gps = GpsCoordinator(hass, host, port)

    # NTP has to work for the entry to be useful. GPS is allowed to fail here:
    # a receiver with no fix is a normal state and its entities can come up
    # later without blocking setup.
    await ntp.async_config_entry_first_refresh()
    await gps.async_refresh()

    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = {"ntp": ntp, "gps": gps}
    await _async_register_frontend(hass)
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unloaded
