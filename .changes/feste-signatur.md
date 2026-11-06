# Keine Passwortabfrage mehr nach Updates

## Was wurde verbessert?

Bisher fragte macOS nach jedem Update nach dem Schlüsselbund-Passwort, weil jede Version eine wechselnde Ad-hoc-Signatur hatte und für den Schlüsselbund wie eine fremde App aussah. Die Mac-App wird jetzt mit dem Apple-Development-Zertifikat des Entwicklers signiert. Der Schlüsselbund erkennt jede neue Version über die Team-ID als dieselbe App. Nur Einträge, die bisher ausschließlich einer früheren Ad-hoc-Version vertrauten, fragen ein letztes Mal.
