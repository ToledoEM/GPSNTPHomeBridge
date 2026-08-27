"""Data update coordinators for GPS & NTP Home Bridge."""

from __future__ import annotations

import logging
from typing import Any

import aiohttp
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import (
    DOMAIN,
    ENDPOINT_GPS,
    ENDPOINT_NTP_CRV,
    ENDPOINT_NTP_PEERS,
    REQUEST_TIMEOUT,
    SCAN_INTERVAL_GPS,
    SCAN_INTERVAL_NTP,
)

_LOGGER = logging.getLogger(__name__)


class BridgeCoordinator(DataUpdateCoordinator):
    """Fetch JSON from the bridge and hand it to the entities."""

    def __init__(self, hass: HomeAssistant, host: str, port: int, name, interval):
        super().__init__(
            hass,
            _LOGGER,
            name=f"{DOMAIN}_{name}",
            update_interval=interval,
        )
        self._session = async_get_clientsession(hass)
        self._base = f"http://{host}:{port}"

    async def _fetch(self, endpoint: str) -> Any:
        """Fetch and decode one endpoint."""
        url = f"{self._base}/{endpoint}"
        try:
            async with self._session.get(
                url, timeout=aiohttp.ClientTimeout(total=REQUEST_TIMEOUT)
            ) as response:
                response.raise_for_status()
                # lighttpd serves these as text/plain, so skip content-type checking
                return await response.json(content_type=None)
        except aiohttp.ClientError as err:
            raise UpdateFailed(f"Error fetching {url}: {err}") from err
        except ValueError as err:
            raise UpdateFailed(f"Invalid JSON from {url}: {err}") from err


class NtpCoordinator(BridgeCoordinator):
    """Poll both NTP endpoints together."""

    def __init__(self, hass: HomeAssistant, host: str, port: int):
        super().__init__(hass, host, port, "ntp", SCAN_INTERVAL_NTP)

    async def _async_update_data(self) -> dict[str, Any]:
        system = await self._fetch(ENDPOINT_NTP_CRV)
        peers = await self._fetch(ENDPOINT_NTP_PEERS)

        if not isinstance(system, dict):
            raise UpdateFailed("Unexpected payload from the NTP status endpoint")
        if not isinstance(peers, list):
            peers = []

        # ntp_service.sh writes this when ntpq itself fails
        if "error" in system:
            raise UpdateFailed(system["error"])

        return {"system": system, "peers": peers}


class GpsCoordinator(BridgeCoordinator):
    """Poll the GPS endpoint."""

    def __init__(self, hass: HomeAssistant, host: str, port: int):
        super().__init__(hass, host, port, "gps", SCAN_INTERVAL_GPS)

    async def _async_update_data(self) -> dict[str, Any]:
        data = await self._fetch(ENDPOINT_GPS)

        if not isinstance(data, dict):
            raise UpdateFailed("Unexpected payload from the GPS endpoint")

        # gpsserver.sh writes this when gpsd has nothing to give. The receiver
        # losing its fix is a normal state, so report zeros rather than failing
        # the whole update and marking every entity unavailable.
        if "error" in data:
            _LOGGER.debug("GPS endpoint reported: %s", data["error"])

        return data
