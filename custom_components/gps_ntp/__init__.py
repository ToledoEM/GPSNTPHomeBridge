"""The GPS & NTP Home Bridge integration."""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant

from .const import CONF_HOST, CONF_PORT, DOMAIN
from .coordinator import GpsCoordinator, NtpCoordinator

PLATFORMS: list[Platform] = [Platform.SENSOR]


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
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unloaded
