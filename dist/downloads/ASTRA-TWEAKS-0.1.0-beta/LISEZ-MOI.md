# ASTRA TWEAKS — 0.1.0 bêta

Suite Windows portable. Première version en développement, non signée numériquement.

## Démarrer

1. Extrayez toute l'archive dans un dossier.
2. Ouvrez **ASTRA TWEAKS.exe**. Gardez tous les fichiers dans le même dossier.
3. Cliquez sur **Analyser / Actualiser**, puis explorez **Optimisations**.
4. Examinez les valeurs proposées, choisissez vos réglages et confirmez.
5. Pour annuler, ouvrez **Restauration**, en commençant par la dernière opération.

Le lancement ne modifie aucun réglage. Aucun compte, service résident ou envoi de télémétrie. Les profils et réglages sont appliqués uniquement après confirmation dans l'application.

## Langue / Language

Dans l'onglet **Langue**, choisissez **Français** ou **English**. Le bouton **FR / EN** de l'en-tête ouvre aussi cet onglet. Le changement est immédiat, conserve les réglages cochés et mémorise votre choix dans `%LOCALAPPDATA%\AstraTweaks\preferences.json`. Les messages Windows et noms techniques restent dans leur langue d'origine.

Open the **Language** tab, or click **FR / EN** in the header, and choose **Français** or **English**. The interface changes immediately, keeps your selected tweaks and remembers your choice on this PC. Windows messages and technical names keep their original language. Extract every file from the ZIP, including `Astra.Localization.psm1` and `translations.en.json`.

## Configuration

Windows 11 ou Windows 10 build 19045+, Windows PowerShell 5.1, WPF et .NET Framework. La compatibilité dépend du matériel et des politiques de votre poste. Le lanceur utilise une stratégie d'exécution PowerShell limitée à son processus, sans changement permanent. Le programme n'est pas signé par un certificat d'éditeur ; respectez les protections et règles de votre appareil.

## Inclus

- 12 préférences utilisateur (Gaming, Interface, Windows, Confidentialité), sauvegardées et vérifiées.
- 3 profils powercfg créés comme copies du plan actif : Performance, Balanced, Eco.
- Instantané local CPU, RAM disponible, GPU/pilotes/fréquence WMI, disques, Defender et pare-feu.
- Inventaire du démarrage en lecture seule et raccourcis vers les réglages Windows.
- 6 requêtes ICMP à l'IP choisie, moyenne, gigue et perte (ne mesure pas un serveur de jeu).
- Import et comparaison de 2 CSV de frametimes (FrameTimeMs ou MsBetweenPresents).
- Export JSON local des informations système.
- Historique et restauration en ordre inverse, avec protection des modifications externes conflictuelles.

## Sauvegardes

Les journaux se trouvent dans `%LOCALAPPDATA%\AstraTweaks`. Conservez-les tant que vous utilisez les modifications. Ils contiennent uniquement les valeurs concernées et les identifiants des plans. Ils ne remplacent pas une sauvegarde système ou de vos fichiers.

En cas d'interruption, les nouvelles modifications restent bloquées jusqu'à résolution de l'opération incomplète. Si une valeur a changé en dehors d'ASTRA, la restauration signale un conflit et ne l'écrase pas. Les clés de registre créées peuvent rester vides après restauration. Une erreur de permissions peut empêcher une restauration : conservez le journal pour diagnostiquer le problème.

## Profils

| Profil | CPU secteur | EPP secteur | CPU batterie |
|---|---|---|---|
| Performance | 5–100 % | 25 | 5–80 % |
| Balanced | 5–100 % | 50 | 5–80 % |
| Eco | 5–80 % | 80 | 5–80 % |

EPP = préférence énergétique, pas gain de performances. L'EPP sur batterie et les autres options sont hérités du plan actuel. Les plans et options peuvent être refusés sur certains matériels ; l'application tente alors un retour arrière.

## Frametime CSV

Colonne `FrameTimeMs` ou `MsBetweenPresents`, valeurs positives en millisecondes avec point décimal, au moins 100 lignes, 20 Mo maximum. Une seule session et un seul processus par CSV. ASTRA n'effectue pas lui-même la capture FPS. FPS moyens = 1000 / moyenne des frametimes. Low = 1000 / moyenne des 1 % ou 0,1 % de frametimes les plus lents, arrondis au supérieur. Comparer même scène, durée, matériel, pilotes et réglages.

## Limites

Pas de capture FPS/DPC, mesure de température, charge GPU, overclocking ou mode Adaptatif. Pas de gain de FPS garanti ni de réduction universelle du ping. Les préférences d'interface et de confidentialité visent principalement le confort. Aucune désactivation de Defender, du pare-feu, de Windows Update ou du fichier d'échange. La vérification du registre confirme l'écriture ; son effet peut varier selon Windows et nécessiter une nouvelle connexion. Les tests automatisés utilisent des fournisseurs simulés et ne constituent pas une validation sur toutes les configurations matérielles.

Le diagnostic réseau contacte l'IP choisie uniquement à votre demande. Les rapports sont locaux et peuvent contenir les noms du matériel et des processus. Le taux de rafraîchissement WMI est indicatif, à vérifier dans Windows.

## Sources & reconstruction

Les fichiers `.ps1`, `.psm1`, `.xaml`, `catalog.json` et `Launcher.cs` sont le code source. Le lanceur se reconstruit avec le compilateur C# .NET Framework et la référence System.Windows.Forms.dll. Le projet de travail contient aussi `build.ps1` et les tests du moteur.

Documentation Microsoft :
- https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
- https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-common
- https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11

Copyright 2026 ASTRA TWEAKS. Projet livré au propriétaire pour développement et validation ; aucune licence tierce n'est intégrée.
