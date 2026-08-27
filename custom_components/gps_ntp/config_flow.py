"""Config flow for GPS & NTP Home Bridge."""

from __future__ import annotations

from typing import Any

import aiohttp
import voluptuous as vol
from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .const import (
    CONF_HOST,
    CONF_PORT,
    DEFAULT_PORT,
    DOMAIN,
    ENDPOINT_NTP_CRV,
    REQUEST_TIMEOUT,
)

STEP_USER_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_HOST): str,
        vol.Optional(CONF_PORT, default=DEFAULT_PORT): int,
    }
)


class GpsNtpConfigFlow(ConfigFlow, domain=DOMAIN):
    """Ask for the address of the machine running the bridge."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        errors: dict[str, str] = {}

        if user_input is not None:
            host = user_input[CONF_HOST].strip()
            port = user_input[CONF_PORT]

            await self.async_set_unique_id(f"{host}:{port}")
            self._abort_if_unique_id_configured()

            error = await self._async_check_endpoint(host, port)
            if error:
                errors["base"] = error
            else:
                return self.async_create_entry(
                    title=f"GPS & NTP Bridge ({host})",
                    data={CONF_HOST: host, CONF_PORT: port},
                )

        return self.async_show_form(
            step_id="user", data_schema=STEP_USER_SCHEMA, errors=errors
        )

    async def _async_check_endpoint(self, host: str, port: int) -> str | None:
        """Confirm the host actually serves the bridge. Returns an error key."""
        session = async_get_clientsession(self.hass)
        url = f"http://{host}:{port}/{ENDPOINT_NTP_CRV}"
        try:
            async with session.get(
                url, timeout=aiohttp.ClientTimeout(total=REQUEST_TIMEOUT)
            ) as response:
                response.raise_for_status()
                await response.json(content_type=None)
        except aiohttp.ClientResponseError:
            # Something answered, but not the bridge
            return "invalid_endpoint"
        except aiohttp.ClientError:
            return "cannot_connect"
        except ValueError:
            return "invalid_endpoint"
        return None
