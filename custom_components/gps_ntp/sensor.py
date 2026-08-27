"""Sensors for GPS & NTP Home Bridge."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import PERCENTAGE, EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import CONF_HOST, DOMAIN


def _to_float(value: Any) -> float | None:
    """The NTP parser emits everything as strings."""
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _to_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


@dataclass(frozen=True, kw_only=True)
class BridgeSensorDescription(SensorEntityDescription):
    """A sensor plus how to pull its value out of the coordinator data."""

    value_fn: Callable[[dict[str, Any]], Any]
    attributes_fn: Callable[[dict[str, Any]], dict[str, Any]] | None = None


NTP_SENSORS: tuple[BridgeSensorDescription, ...] = (
    BridgeSensorDescription(
        key="stratum",
        name="NTP stratum",
        icon="mdi:server-network",
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda d: _to_int(d["system"].get("stratum")),
        attributes_fn=lambda d: {
            "refid": d["system"].get("refid"),
            "status": d["system"].get("status"),
            "status_flags": d["system"].get("status_flags", []),
        },
    ),
    BridgeSensorDescription(
        key="frequency",
        name="NTP frequency offset",
        icon="mdi:speedometer",
        native_unit_of_measurement="ppm",
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda d: _to_float(d["system"].get("frequency")),
    ),
    BridgeSensorDescription(
        key="sys_jitter",
        name="NTP system jitter",
        icon="mdi:chart-line",
        native_unit_of_measurement="ms",
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=3,
        value_fn=lambda d: _to_float(d["system"].get("sys_jitter")),
    ),
    BridgeSensorDescription(
        key="clk_jitter",
        name="NTP clock jitter",
        icon="mdi:clock",
        native_unit_of_measurement="ms",
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=3,
        value_fn=lambda d: _to_float(d["system"].get("clk_jitter")),
    ),
    BridgeSensorDescription(
        key="clk_wander",
        name="NTP clock wander",
        icon="mdi:clock-alert",
        native_unit_of_measurement="ppm",
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=4,
        value_fn=lambda d: _to_float(d["system"].get("clk_wander")),
    ),
    BridgeSensorDescription(
        key="offset",
        name="NTP offset",
        icon="mdi:swap-horizontal",
        native_unit_of_measurement="ms",
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=3,
        value_fn=lambda d: _to_float(d["system"].get("offset")),
    ),
    BridgeSensorDescription(
        key="precision",
        name="NTP precision",
        icon="mdi:target",
        entity_category=EntityCategory.DIAGNOSTIC,
        value_fn=lambda d: _to_int(d["system"].get("precision")),
    ),
    BridgeSensorDescription(
        key="synced_peer",
        name="NTP synced peer",
        icon="mdi:server-network",
        # The peer carrying the "*" tally is the one the clock is actually
        # following. Without it there is no sync source.
        value_fn=lambda d: next(
            (p.get("remote") for p in d["peers"] if p.get("tally") == "*"), None
        ),
        attributes_fn=lambda d: {"peers": d["peers"]},
    ),
    BridgeSensorDescription(
        key="peer_count",
        name="NTP peer count",
        icon="mdi:server",
        state_class=SensorStateClass.MEASUREMENT,
        entity_category=EntityCategory.DIAGNOSTIC,
        value_fn=lambda d: len(d["peers"]),
    ),
    BridgeSensorDescription(
        key="reachable_peers",
        name="NTP reachable peers",
        icon="mdi:lan-connect",
        state_class=SensorStateClass.MEASUREMENT,
        # reach is the 8-bit poll history; anything above 0 means the peer
        # answered at least one of the last eight polls.
        value_fn=lambda d: sum(1 for p in d["peers"] if p.get("reach", 0) > 0),
    ),
)


GPS_SENSORS: tuple[BridgeSensorDescription, ...] = (
    BridgeSensorDescription(
        key="used_satellites",
        name="GPS satellites used",
        icon="mdi:satellite-variant",
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda d: d.get("used_satellites", 0),
    ),
    BridgeSensorDescription(
        key="total_satellites",
        name="GPS satellites visible",
        icon="mdi:satellite-variant",
        state_class=SensorStateClass.MEASUREMENT,
        value_fn=lambda d: d.get("total_satellites", 0),
        attributes_fn=lambda d: {"satellites": d.get("satellites", [])},
    ),
    BridgeSensorDescription(
        key="satellite_ratio",
        name="GPS satellite ratio",
        icon="mdi:percent",
        native_unit_of_measurement=PERCENTAGE,
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=1,
        value_fn=lambda d: d.get("satellite_ratio", 0),
    ),
    BridgeSensorDescription(
        key="avg_signal_strength",
        name="GPS average signal strength",
        icon="mdi:signal-variant",
        # gpsd reports ss in dB-Hz
        native_unit_of_measurement="dBHz",
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=2,
        value_fn=lambda d: d.get("avg_signal_strength", 0),
        attributes_fn=lambda d: d.get("gnss_breakdown", {}),
    ),
    BridgeSensorDescription(
        key="hdop",
        name="GPS HDOP",
        icon="mdi:crosshairs-gps",
        state_class=SensorStateClass.MEASUREMENT,
        suggested_display_precision=2,
        value_fn=lambda d: (d.get("dop_values") or {}).get("hdop"),
        attributes_fn=lambda d: d.get("dop_values") or {},
    ),
    BridgeSensorDescription(
        key="timestamp",
        name="GPS fix timestamp",
        device_class=SensorDeviceClass.TIMESTAMP,
        entity_category=EntityCategory.DIAGNOSTIC,
        value_fn=lambda d: _parse_timestamp(d.get("timestamp")),
    ),
)


def _parse_timestamp(value: Any):
    """gpsd emits an ISO 8601 string; HA wants an aware datetime."""
    if not value:
        return None
    from homeassistant.util import dt as dt_util

    return dt_util.parse_datetime(value)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the sensors."""
    data = hass.data[DOMAIN][entry.entry_id]
    host = entry.data[CONF_HOST]

    entities: list[BridgeSensor] = [
        BridgeSensor(data["ntp"], description, entry, host)
        for description in NTP_SENSORS
    ]
    entities.extend(
        BridgeSensor(data["gps"], description, entry, host)
        for description in GPS_SENSORS
    )

    async_add_entities(entities)


class BridgeSensor(CoordinatorEntity, SensorEntity):
    """A single value read from one of the bridge endpoints."""

    _attr_has_entity_name = True
    entity_description: BridgeSensorDescription

    def __init__(self, coordinator, description, entry, host):
        super().__init__(coordinator)
        self.entity_description = description
        self._attr_unique_id = f"{entry.entry_id}_{description.key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.entry_id)},
            name=f"GPS & NTP Bridge ({host})",
            manufacturer="GPSNTPHomeBridge",
            configuration_url=f"http://{host}",
        )

    @property
    def available(self) -> bool:
        return super().available and self.coordinator.data is not None

    @property
    def native_value(self) -> Any:
        try:
            return self.entity_description.value_fn(self.coordinator.data)
        except (KeyError, TypeError, AttributeError):
            return None

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        if self.entity_description.attributes_fn is None:
            return None
        try:
            return self.entity_description.attributes_fn(self.coordinator.data)
        except (KeyError, TypeError, AttributeError):
            return None
