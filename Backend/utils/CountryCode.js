const {
    parsePhoneNumberFromString,
    getCountryCallingCode,
} = require("libphonenumber-js");

/**
 * Global Phone Number Parser Utility
 * Extracts exact Country Code (+92, +1, etc.), ISO, and Local National Number
 */
const parseGlobalPhoneNumber = (inputPhone, defaultCountryIso = null) => {
    const raw = String(inputPhone || "").trim();

    if (!raw) {
        return {
            isValid: false,
            countryCode: null,
            countryIso: null,
            formattedLocal: "",
            fullInternational: "",
        };
    }

    let parsed = null;

    if (raw.startsWith("+")) {
        parsed = parsePhoneNumberFromString(raw);
    } else {
        parsed = parsePhoneNumberFromString(`+${raw}`);

        if ((!parsed || !parsed.isValid()) && defaultCountryIso) {
            parsed = parsePhoneNumberFromString(
                raw,
                defaultCountryIso.toUpperCase()
            );
        }
    }

    if (parsed && parsed.isValid()) {
        return {
            isValid: true,
            countryCode: `+${parsed.countryCallingCode}`,
            countryIso: parsed.country,
            formattedLocal: parsed.nationalNumber.toString(),
            fullInternational: parsed.format("E.164"),
        };
    }

    const cleanDigits = raw.replace(/[^\d+]/g, "");
    let fallbackCode = null;
    let fallbackIso = null;

    if (defaultCountryIso && !cleanDigits.startsWith("+")) {
        try {
            const iso = defaultCountryIso.toUpperCase();
            fallbackCode = `+${getCountryCallingCode(iso)}`;
            fallbackIso = iso;
        } catch (error) {
            fallbackCode = null;
            fallbackIso = null;
        }
    }

    return {
        isValid: false,
        countryCode: fallbackCode,
        countryIso: fallbackIso,
        formattedLocal: cleanDigits.replace(/^\+/, ""),
        fullInternational: cleanDigits.startsWith("+")
            ? cleanDigits
            : fallbackCode
                ? `${fallbackCode}${cleanDigits.replace(/^0/, "")}`
                : cleanDigits,
    };
};

module.exports = {
    parseGlobalPhoneNumber,
};
