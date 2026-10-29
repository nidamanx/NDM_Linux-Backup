# NDM Linux Backup

[English](README.md) · **Italiano**

[![License: AGPL
v3+](https://img.shields.io/badge/License-AGPL_v3%2B-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-3.0.1-informational)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25)

**NDM Linux Backup** è uno strumento di backup di sistema e disaster recovery per server
e workstation Debian/GNU Linux. Salva le parti di una macchina che servono per
ricostruirla o diagnosticarla, quelle che la maggior parte dei software di backup
trascura: inventario hardware, configurazione di avvio (UEFI/BIOS/MBR, GRUB), tabelle
delle partizioni, struttura LUKS e LVM, pacchetti installati, file di `/etc` modificati,
crontab, schemi dei database MySQL/MariaDB e PostgreSQL, configurazione di Docker e
Podman. Cifratura GPG e retention dei vecchi archivi sono integrate.

È un unico script Bash senza librerie aggiuntive: usa gli strumenti standard di Debian
installabili con `apt` e gira come root. Ogni impostazione vive nello script stesso,
opzionalmente sovrascrivibile da un file di impostazioni fatto di semplici righe
`KEY=value`, che viene solo letto e mai eseguito (vedi
[File di impostazioni esterno](#file-di-impostazioni-esterno)).

Ogni singola parte del backup può essere attivata o disattivata individualmente (vedi
[Configurazione](#configurazione)), così puoi ridurre lo script a produrre solo ciò di
cui la tua macchina ha davvero bisogno.

Il backup stesso è diviso in un massimo di tre archivi: **settings** (hardware,
configurazioni, elenchi pacchetti, schema dei database, metadati/config dei container...
tutto ciò che serve per capire o ricostruire l'impostazione) viene sempre prodotto;
**data** (righe reali dei database, contenuto reale dei volumi Docker/Podman, i tuoi
documenti) e **secrets** (chiavi host SSH, chiavi private TLS, `/etc/shadow`,
credenziali di rete, credenziali proprie di root...) sono archivi separati e opzionali
(vedi [Backup dei dati](#backup-dei-dati) e [Backup dei segreti](#backup-dei-segreti)).
L'archivio settings non contiene mai materiale dell'archivio secrets, indipendentemente
dal fatto che l'archivio secrets stesso sia abilitato o meno.

## Perché

La maggior parte dei software di backup salva i tuoi file. Quando un disco si rompe o
una macchina va ricostruita, spesso manca tutto quello che sta intorno: quali dischi e
partizioni c'erano, come erano organizzati LUKS e LVM, come si avviava la macchina,
quali pacchetti erano stati installati a mano, quali file di `/etc` erano stati
modificati, gli schemi dei database, la configurazione dei container. NDM Linux Backup
raccoglie esattamente questo, in archivi leggibili con gli strumenti standard.

Non sostituisce i software di backup dei file o delle immagini disco come Back In Time,
Timeshift o Clonezilla: li completa, salvando le parti del sistema che loro trascurano.

---

## Indice

- [Cosa viene salvato](#cosa-viene-salvato)
- [Sicurezza](#sicurezza)
- [Backup dei dati](#backup-dei-dati)
- [Backup dei segreti](#backup-dei-segreti)
- [Cifratura](#cifratura)
- [Requisiti](#requisiti)
- [Installazione](#installazione)
  - [Solo lo script](#solo-lo-script)
  - [Aggiornamento](#aggiornamento)
- [Utilizzo](#utilizzo)
- [Configurazione](#configurazione)
  - [File di impostazioni esterno](#file-di-impostazioni-esterno)
  - [Backup MySQL/MariaDB](#backup-mysqlmariadb)
  - [Backup PostgreSQL](#backup-postgresql)
- [Notifiche](#notifiche)
- [Cron](#cron)
- [Analisi](#analisi)
- [Ripristino](#ripristino)
  - [Archivio settings](#archivio-settings)
  - [Archivio data](#archivio-data)
  - [Archivio secrets](#archivio-secrets)
- [Esempio di output](#esempio-di-output)
- [Servizi esterni contattati](#servizi-esterni-contattati)
- [Codici di uscita](#codici-di-uscita)
- [Struttura del progetto](#struttura-del-progetto)
- [Versioni](#versioni)
- [Licenza e disclaimer](#licenza-e-disclaimer)

---

## Cosa viene salvato

Sistema e hardware:
- Informazioni hardware
- Elenco dispositivi hardware
- Report completo di sistema (`inxi`)
- Release GNU/Linux
- Release del kernel Linux

Avvio e dischi:
- Elenco dei block device (`lsblk`)
- ID a blocchi dei dispositivi installati (richiede root)
- UEFI (richiede root)
- BIOS MBR (richiede root)
- Configurazione LUKS (richiede root) -- dump testuale di sola consultazione (UUID,
  cifra, disposizione dei keyslot; nessun materiale chiave), non un header
  ripristinabile. Un backup separato, più sensibile, dell'header raw -- capace di
  ripristinare byte per byte un header LUKS corrotto, e che vanifica anche il
  crypto-shredding per chiunque se ne impossessi -- vive nell'archivio secrets
  opzionale, disattivato di default anche lì; vedi [Backup dei
  segreti](#backup-dei-segreti)
- Configurazione LVM (richiede root)
- Informazioni sulle partizioni (richiede root)
- Configurazione Grub

Software e dati:
- Pacchetti installati
- Elenco app Flatpak
- File AppImage trovati sul sistema (dimensione + elenco percorsi, non i file stessi;
  vedi [Configurazione](#configurazione) per aggiungere percorsi di ricerca)
- File di sistema modificati manualmente: qualunque file il cui contenuto non
  corrisponda più a quanto installato dal pacchetto (`dpkg -V`), copiato così com'è;
  intercetta solo file già tracciati da un pacchetto, non file nuovi non pacchettizzati
- File `/etc` non pacchettizzati: il complemento del punto sopra, file sotto `/etc` non
  di proprietà di nessun pacchetto installato (quindi nemmeno `dpkg -V` li vede) -- es.
  `/etc/postgresql/*/main/postgresql.conf`, generato dallo script di post-installazione
  di un pacchetto invece che distribuito al suo interno. Un elenco di esclusione di
  default filtra stato auto-generato, copie di backup di tool/editor, e cache compilate
  che sarebbero altrimenti rumore a ogni run (non file che un amministratore ha
  plausibilmente modificato a mano -- `/etc/motd`, `/etc/hosts`, `/etc/hostname`,
  `/etc/machine-id`, `/etc/network/interfaces` e simili sono deliberatamente lasciati
  dentro, a differenza di versioni precedenti di questo elenco), così come il materiale
  di chiavi private (chiavi host SSH, la chiave snakeoil ssl-cert,
  `/etc/mysql/debian.cnf`...) -- che ora vive invece nell'archivio secrets opzionale,
  vedi [Backup dei segreti](#backup-dei-segreti). `/etc/fstab`/`/etc/crypttab` hanno
  nello specifico una propria copia dedicata altrove (`partitions/fstab.txt`,
  `luks/crypttab.txt`) invece di comparire qui -- eccetto crypttab, che compare comunque
  anche qui ogni volta che il modulo LUKS non è girato, così non manca mai
  silenziosamente dall'intero archivio
- Crontab (richiede root)
- Schema MySQL/MariaDB (solo struttura: tabelle, viste, trigger, routine; nessuna riga
  di dati. Richiede root)
- Schema PostgreSQL (come sopra)
- Informazioni su immagini/container/volumi/reti Docker (solo elenchi nome/id; immagini
  e container stessi non vengono mai salvati, sono pensati per essere ricreati dai file
  Compose/Quadlet sopra più il loro registry)
- File Compose trovati sul sistema: Docker Compose / podman-compose (cerca nelle
  posizioni comuni, vedi [Configurazione](#configurazione) per aggiungere percorsi di
  ricerca; copiati così come sono, non solo elencati)
- Informazioni su immagini/container/volumi/reti Podman (solo elenchi nome/id, stesso
  ragionamento di Docker sopra; legge lo stato rootless di `v_podman_user`, vedi
  [Configurazione](#configurazione)) più i suoi file di config e le unit Quadlet
  (systemd), sia a livello di sistema (`/etc/containers`) sia per `v_podman_user`
  (`~/.config/containers`)
- Altre directory scelte dall'utente (potrebbe richiedere root)

Tutto questo viene compresso in un unico archivio settings `tar.xz` in una directory a
scelta. Opzionalmente, la directory dell'archivio può anche essere sincronizzata verso
una destinazione locale o remota tramite rsync, e puoi eseguire tuoi comandi prima e
dopo il backup. Vedi [Backup dei dati](#backup-dei-dati) per l'archivio dati separato e
opzionale.

## Sicurezza

- **Le scritture sono confinate.** Lo script scrive solo ed esclusivamente dentro la
  destinazione del backup e la propria directory di lavoro. Ogni altro percorso del
  sistema (dischi, `/boot`, `/etc`, header LUKS, MySQL...) viene solo letto. Ogni
  chiamata a `tar`/`chmod`/`chown`/`sha256sum`/`gpg`/`rm` è inoltre verificata a runtime
  contro quella stessa whitelist appena prima di essere eseguita, uscendo con errore
  invece di procedere se un percorso risultasse mai fuori da essa.
- **Dry run.** `--dry-run` attraversa realmente ogni passo (leggendo dischi, header
  LUKS, database MySQL, ecc., con privilegi root) senza creare, modificare o eliminare
  nulla, così puoi validare la tua configurazione in sicurezza prima di un run reale.
- **Percorsi sorgente sovrapposti.** Se `v_tempdir`/`v_tempdir_data` viene spostato
  (tramite `ndm_linux-backup.conf`) da qualche parte sotto una voce di
  `a_source_extra`/`a_data_source_extra`, lo script avvisa (senza bloccare il run) che
  il suo contenuto finirà duplicato nell'archivio risultante -- entrambi finiscono per
  essere argomenti sorgente separati sulla stessa riga di comando `tar`. Sposta il
  tempdir fuori da ogni percorso source-extra per far sparire l'avviso; vedi il commento
  di `v_tempdir` in CONFIGURE per capire perché il default non si sovrappone mai. Un
  `v_tempdir`/`_data`/`_secrets` spostato nello stesso posto del proprio
  `v_dest`/`_data`/ `_secrets`, o sotto di esso, è un caso più serio -- l'archivio
  risulterebbe vuoto -- quindi in questo caso lo script esce con errore invece di
  limitarsi ad avvisare.
- **Verifica delle dipendenze.** A ogni run, lo script elenca ogni tool esterno che può
  usare, riporta cosa manca, e ti lascia scegliere cosa fare: installare solo ciò che
  serve ai pezzi di backup che hai abilitato (default) o tutto ciò che lo script
  potrebbe mai usare -- in entrambi i casi, il comando `apt-get install` esatto viene
  stampato prima di essere eseguito -- installarlo tu stesso (stampa il comando esatto
  per Debian, poi esce così puoi eseguirlo e rilanciare NDM Linux Backup una volta
  fatto), oppure saltare e continuare con quei passi che falliscono/vengono saltati. Del
  tutto saltato in `--quiet`/`--dry-run`.
- **Verifica delle credenziali database.** Se il backup MySQL/MariaDB o PostgreSQL è
  abilitato e il suo client è presente, lo script controlla che il file di credenziali
  (`.my.cnf`/`.pgpass`) esista prima di fare qualunque lavoro; se non c'è, prova prima
  una connessione locale via socket (`root@localhost` per MySQL/MariaDB, peer/ident per
  PostgreSQL) e stampa cosa manca e come crearlo, poi esce, solo se anche questo
  fallisce -- non crea, copia o modifica mai il file da solo (vedi [Backup
  MySQL/MariaDB](#backup-mysqlmariadb) e [Backup PostgreSQL](#backup-postgresql)). Se il
  file esiste ma è leggibile da gruppo/altri, lo script stampa un avviso (contiene una
  password in chiaro) senza bloccare il run -- fai `chmod 600` per far sparire l'avviso.
- **Log del run.** Ogni run (eccetto `--dry-run`) scrive un file `.log` in testo
  semplice, leggibile da tutti (`chmod 644`), nella destinazione del backup accanto
  all'archivio settings -- il resoconto completo, passo per passo, di cosa è successo,
  indipendente da `--quiet` (che silenzia solo il terminale, non il log), così i run non
  presidiati/via cron lasciano comunque una traccia completa da controllare in seguito.
- **Checksum.** Ogni archivio (settings, data, secrets) riceve un file
  `<nomefile>.tar.xz.sha256` scritto proprio accanto ad esso, nel formato standard
  `sha256sum`. Verifica con `sha256sum -c <nomefile>.tar.xz.sha256` dalla directory di
  destinazione -- vale la pena farlo prima di fidarsi di un vecchio backup per un
  ripristino reale, dato che un `tar.xz` silenziosamente corrotto (problema del disco,
  una copia interrotta altrove) sembra ancora un file normale finché non provi davvero a
  leggerlo. Un fallimento del checksum viene registrato come avviso e non fa fallire il
  run: l'archivio stesso era già stato creato con successo a quel punto.
- **Retention.** Disattivata di default (`v_retention_days=0`): i vecchi archivi vengono
  conservati per sempre a meno che tu non attivi l'opzione. Quando attiva, elimina gli
  archivi (settings/data/secrets contati separatamente) più vecchi di
  `v_retention_days`, mantenendo sempre almeno `v_retention_min_keep` di ciascun tipo
  indipendentemente dall'età -- così una macchina rimasta inutilizzata oltre la finestra
  di retention non si ritrova mai a zero backup al run successivo. Viene eseguita subito
  dopo che un nuovo archivio di quel tipo è stato creato con successo, prima del passo
  rsync (così un `v_dest_rsync` sincronizzato riflette anche lo stato ripulito), e
  corrisponde solo ed esclusivamente al pattern di nome file esatto di questo script.
- **Cifratura.** Disattivata di default
  (`v_enable_gpg_settings`/`_data`/`_secrets=false`). `chmod 600` protegge un archivio
  solo finché resta sul filesystem di questa macchina; se viene mai copiato da qualche
  parte meno protetta (una chiavetta USB, un cloud storage, un disco esterno non
  cifrato), quella protezione sparisce. Quando un interruttore è attivo, il suo archivio
  viene cifrato con GPG subito dopo essere stato creato (usando
  `v_gpg_recipient_file`/`_data`/`_secrets`, default `${HOME}/pubkey.asc`) e il testo in
  chiaro viene eliminato -- la chiave privata non serve mai sulla macchina di backup,
  solo più tardi, su qualunque macchina userai davvero per il ripristino (vedi
  [Ripristino](#ripristino)). Un interruttore attivo senza una chiave destinataria a
  quel percorso interrompe il run prima che inizi qualunque lavoro di backup (vedi
  [Cifratura](#cifratura)); anche una cifratura fallita interrompe il run con errore,
  invece di lasciare silenziosamente un archivio in chiaro.
- **Il file di impostazioni non viene mai eseguito.** `ndm_linux-backup.conf` viene
  letto riga per riga come `KEY=value`: sono accettate solo le impostazioni della
  sezione CONFIGURE, ogni valore viene controllato in base al suo tipo (true/false,
  numero, percorso assoluto...) e nulla viene espanso o eseguito -- `$HOME`, `$(...)` e
  i backtick vengono rifiutati. Un'impostazione sconosciuta o un valore non valido
  fermano lo script con codice di uscita 2 e indicano la riga. Neanche l'ambiente viene
  letto. Gli unici valori che finiscono eseguiti sono i comandi hook (`v_pre_command`,
  `v_post_command`, `v_on_failure_command`), ciascuno solo quando il suo interruttore
  `v_enable_*` è attivo.
- **Fiducia nello script e nel file di impostazioni.** `ndm_linux-backup.sh` gira come
  root nel momento in cui lo lanci con `sudo`, e i comandi hook di
  `ndm_linux-backup.conf` girano anch'essi come root, senza alcun controllo di
  proprietà/permessi su nessuno dei due file. Nessuno dei due deve essere di proprietà
  di `root`: funzionano bene di proprietà del tuo utente normale, come qualunque altro
  script che lanci con `sudo`. Se più persone condividono questa macchina e vuoi essere
  sicuro che solo tu (o root) possiate modificarli prima del prossimo run, blocca
  entrambi allo stesso modo:
  ```
  sudo chown root:root ndm_linux-backup.sh ndm_linux-backup.conf
  sudo chmod 755 ndm_linux-backup.sh
  sudo chmod 644 ndm_linux-backup.conf
  ```
  Del tutto opzionale, e una scelta tua -- NDM Linux Backup stesso non lo richiede né lo
  verifica mai.
- **Cartella di destinazione del backup.** `v_dest` (e `_data`/`_secrets`) viene creata
  con qualunque modalità produca il tuo umask (tipicamente `755 root:root` --
  elencabile, non scrivibile, da altri utenti), e ogni archivio al suo interno è
  comunque già bloccato individualmente (`chmod 600`, vedi Cifratura sopra). Se vuoi
  anche che la cartella stessa non sia elencabile da altri utenti su una macchina
  condivisa:
  ```
  sudo chmod 700 /percorso/del/backup
  ```
  Opzionale, come sopra -- i permessi dei singoli archivi sono comunque la protezione
  reale.

> [!WARNING]
> **L'archivio settings non è ancora una zona priva di segreti, solo priva di
> *materiale* segreto.** `/etc` e `/root` vengono spazzati per intero di default
> (`a_source_extra`), e la configurazione di sistema può ancora legittimamente contenere
> dettagli sensibili anche dopo che il materiale ad alto rischio conosciuto (chiavi
> private, `/etc/shadow`, credenziali di rete/cloud -- vedi [Backup dei
> segreti](#backup-dei-segreti)) ne è stato escluso. I file `.my.cnf`/`.pgpass` sono
> allo stesso modo sempre esclusi dagli archivi settings e data anche se finissero sotto
> un percorso `a_source_extra`/`a_data_source_extra` (autenticano lo script verso un
> database esterno, non sono configurazione della macchina). Proteggi di conseguenza i
> file `.tar.xz` risultanti (permessi dei file, dove li conservi o li sincronizzi via
> rsync); l'archivio secrets, quando attivo, ha bisogno di quella protezione ancora di
> più.

## Backup dei dati

Disattivato di default (`v_enable_data_backup=false`). Quando attivo, viene prodotto un
secondo archivio `tar.xz` accanto a quello settings, con dati reali. Deliberatamente non
incluso nemmeno qui: le immagini e i container Docker/Podman stessi, dato che sono
pensati per essere ricreati da ciò che l'archivio settings ha già (file Compose/Quadlet,
nomi/tag delle immagini) più il registry, non ripristinati byte per byte. Cosa contiene
davvero l'archivio data:
- Righe dei database MySQL/MariaDB e PostgreSQL (il loro schema è sempre nell'archivio
  settings indipendentemente da questo interruttore, vedi [Cosa viene
  salvato](#cosa-viene-salvato))
- Contenuto reale dei **volumi** Docker/Podman (`v_enable_docker_volumes_data` /
  `v_enable_podman_volumes_data`), letto tramite il Mountpoint di ciascun volume;
  funziona solo con il driver "local" di default. Copiare un volume attivamente scritto
  da un container in esecuzione può produrre una copia incoerente, stessa avvertenza del
  copiare direttamente una directory dati di un database live, quindi per i volumi dei
  database preferisci invece i dump dati di MySQL/PostgreSQL.
- Qualunque directory in `a_data_source_extra` (es. documenti personali, media)

Questo passo ha una propria directory di lavoro e destinazione (`v_tempdir_data` /
`v_dest_data`, di default accanto a quelle dell'archivio settings) e un proprio nome di
file archivio (`..._DATA_...`), così può essere instradato, conservato o programmato
indipendentemente dall'archivio settings. `--dry-run`/`--quiet`/`--keep` si applicano ad
esso esattamente come al passo settings, nessun flag separato necessario.

## Backup dei segreti

Disattivato di default (`v_enable_secrets_backup=false`). Attivalo in modo permanente in
CONFIGURE, oppure passa `--secrets` sulla riga di comando per produrlo per un singolo
run senza toccare affatto CONFIGURE (utile per un occasionale "prendi anche i segreti
stavolta" senza cambiare cosa farà ogni run futuro di default; attiva il passo solo per
quel run, non lo disattiva mai se CONFIGURE lo aveva già abilitato). In entrambi i casi,
viene prodotto un terzo archivio `tar.xz`, contenente materiale sensibile di
credenziali/chiavi che gli archivi settings e data non includono mai, a prescindere da
questo interruttore: chiavi private host SSH, chiavi private TLS (`/etc/ssl/private`,
Let's Encrypt), `/etc/shadow`/`/etc/gshadow` (più le loro copie di backup con `-`),
credenziali di rete NetworkManager/wpa_supplicant/WireGuard, segreti di mail relay e
PPP, le credenziali proprie di root per SSH/CLI cloud/registry Docker e la sua bash
history, e le credenziali proprie di questo script `.my.cnf`/`.pgpass` (a differenza di
ovunque altro, l'archivio secrets è dove questi appartengono, dato che esiste apposta
per contenere credenziali utili al momento del ripristino). L'elenco esatto è
`a_secrets_source` in CONFIGURE, liberamente sovrascrivibile; un percorso mancante viene
saltato con un avviso, non un errore, dato che non ogni macchina ha tutti questi
elementi.

Questo passo ha una propria directory di lavoro e destinazione (`v_tempdir_secrets` /
`v_dest_secrets`, di default accanto a quelle dell'archivio settings) e un proprio nome
di file archivio (`..._SECRETS_...`), così può essere instradato, conservato o protetto
indipendentemente dagli archivi settings/data -- es. permessi più stretti sulla
destinazione, nessun rsync verso una posizione condivisa, una retention più breve.
`--dry-run`/`--quiet`/`--keep` si applicano ad esso esattamente come al passo settings,
nessun flag separato necessario.

> [!WARNING]
> Proteggi questo archivio almeno quanto proteggeresti `/root` e `/etc/shadow` stessi:
> chiunque lo possieda può impersonare questa macchina, decifrare il suo traffico TLS, e
> usare qualunque credenziale cloud/registry che root avesse configurato.

**Backup raw dell'header LUKS** (`v_enable_luks_header_backup`, disattivato di default
anche quando il resto di questo passo è attivo): una vera immagine
`cryptsetup luksHeaderBackup` per ogni voce di `a_luks`, che finisce in `luks_headers/`
dentro questo stesso archivio. È diverso da -- e più sensibile di -- il testo leggibile
`luksDump`/`luksUUID` già presente nell'archivio settings: contiene i keyslot reali (la
master key cifrata con la chiave derivata da ciascuna passphrase), quindi può
ripristinare un header LUKS corrotto byte per byte.

> [!CAUTION]
> Questo **vanifica anche il crypto-shredding** -- distruggere solo l'header su disco
> per rendere un volume permanentemente irrecuperabile, una tecnica su cui alcuni
> amministratori fanno affidamento quando dismettono un disco -- per chiunque se ne
> impossessi. Attivalo solo se vuoi specificamente la garanzia di recupero dell'header
> sopra descritta e accetti questo compromesso; lo script stampa e registra un avviso
> esplicito ogni volta che è attivo, separato dall'avviso generale sul backup dei
> secrets.

## Cifratura

Disattivata di default per tutti e tre gli archivi
(`v_enable_gpg_settings`/`_data`/`_secrets`, vedi [Configurazione](#configurazione) e
[Sicurezza](#sicurezza)) -- `v_enable_gpg_data`/`_secrets` rispecchiano
`v_enable_gpg_settings` a meno che non vengano sovrascritti indipendentemente, stesso
schema di `v_dest_secrets`/`v_tempdir_secrets`: attiva solo `v_enable_gpg_settings` per
cifrare tutti e tre allo stesso modo, oppure lascialo spento e attiva solo
`v_enable_gpg_secrets` per cifrare solo l'archivio secrets. La chiave destinataria reale
di ciascun archivio è `v_gpg_recipient_file`/`_data`/`_secrets`, con default
`${HOME}/pubkey.asc` (di root, stesso posto dove vivono già `.my.cnf`/`.pgpass`) anche
mentre la cifratura stessa è spenta -- impostare il percorso da solo è innocuo, solo
l'interruttore `v_enable_gpg_*` corrispondente attiva davvero la cifratura.

Configurazione iniziale, prima di attivare un interruttore:

1. Genera una coppia di chiavi GPG. Non deve necessariamente accadere sulla macchina di
   backup -- anzi, è meglio se non accade lì, vedi il punto 4:
   ```
   gpg --full-generate-key
   ```
2. Esporta solo la chiave **pubblica** in un file semplice:
   ```
   gpg --armor --export <keyid-o-email> > pubkey.asc
   ```
3. Copia `pubkey.asc` sulla macchina di backup, al percorso a cui
   `v_gpg_recipient_file`/`_data`/`_secrets` già punta (`${HOME}/pubkey.asc` a meno che
   tu non l'abbia cambiato) -- oppure hai già una chiave pubblica di chi farà il
   ripristino di questo backup? Copia quella invece, non serve generarne una tua. Chiavi
   diverse per ogni archivio per un accesso a livelli, es. una chiave ad accesso più
   ampio per settings e una ristretta per secrets? Punta ogni variabile al proprio file
   invece di condividere il default -- vedi [Configurazione](#configurazione) per capire
   perché anche settings non è necessariamente "privo di segreti" prima di decidere di
   lasciarlo in chiaro.
4. Tieni la chiave **privata** completamente fuori dalla macchina di backup. Non serve
   mai lì -- serve solo `pubkey.asc`, per cifrare. La chiave privata serve più tardi,
   solo sulla macchina su cui farai davvero il ripristino (vedi
   [Ripristino](#ripristino)); conservala come faresti con qualunque altra credenziale
   principale -- un password manager, una chiavetta USB offline, un token hardware --
   non sulla macchina di cui fai il backup.
5. Attiva l'interruttore (o gli interruttori) per gli archivi che vuoi cifrati:
   `v_enable_gpg_settings`/`_data`/`_secrets=true`.

Se un interruttore è attivo ma la sua chiave destinataria manca nel momento in cui NDM
Linux Backup gira, esce prima di fare qualunque lavoro e stampa esattamente cosa manca e
come risolverlo (generare una coppia di chiavi, esportare la chiave pubblica, o copiarne
una esistente al posto giusto) -- non crea o modifica mai da solo il materiale delle
chiavi, stesso approccio "controlla e segnala, mai automatizzare la correzione" della
verifica delle credenziali MySQL/PostgreSQL sopra. Se ciascun archivio finisce cifrato o
resta in chiaro viene anche dichiarato all'inizio di ogni run, proprio accanto
all'avviso sul backup dei secrets.

Dal run successivo in poi, ogni archivio il cui interruttore è attivo viene cifrato
automaticamente e il suo testo in chiaro eliminato; nient'altro cambia nel modo in cui
lo script funziona.

## Requisiti

- **Debian GNU/Linux**: testato su Debian 13 (Trixie). Le derivate possono funzionare ma
  non sono testate.
- **Bash** e **privilegi di root** (`sudo` o `su`): altrimenti lo script non parte.
- Gli strumenti delle parti di backup che attivi. A ogni avvio lo script elenca quelli
  mancanti e propone di installarli con `apt-get` (vedi [Sicurezza](#sicurezza),
  "Verifica delle dipendenze"). Uno strumento richiesto da una parte attiva deve
  esserci, altrimenti il run si ferma prima di fare qualsiasi cosa; quelli segnati
  *opzionale*, se mancano, saltano solo la propria parte.

| Pacchetto Debian | Comandi | Serve per | |
|------------------|---------|-----------|---|
| `tar`, `coreutils`, `fdisk` | `tar`, `sha256sum`, `fdisk` | ogni run | obbligatorio |
| `lshw` | `lshw` | informazioni hardware | se attivo |
| `pciutils`, `usbutils` | `lspci`, `lsusb` | elenco dei dispositivi | se attivo |
| `inxi` | `inxi` | report completo del sistema | se attivo |
| `util-linux` | `lsblk`, `blkid` | dispositivi a blocchi | se attivo |
| `coreutils` | `dd`, `uname` | MBR, versione del kernel | se attivo |
| `lsb-release` | `lsb_release` | versione di GNU/Linux | se attivo |
| `fdisk` | `sfdisk` | tabelle delle partizioni | se attivo |
| `dpkg`, `apt` | `dpkg`, `apt-mark` | pacchetti installati, file di sistema modificati | se attivo |
| `cryptsetup` | `cryptsetup` | LUKS, header LUKS raw | se attivo |
| `cron` | `crontab` | crontab | se attivo |
| `rsync` | `rsync` | copia su una seconda destinazione | se attivo |
| `gnupg` | `gpg` | [Cifratura](#cifratura) | se attivo |
| `efibootmgr` | `efibootmgr` | voci di avvio UEFI | opzionale |
| `lvm2` | `lvmdump`, `pvdisplay`, `vgdisplay`, `lvdisplay` | LVM | opzionale |
| `default-mysql-client` | `mysql`, `mysqldump` | MySQL/MariaDB | opzionale |
| `postgresql-client` | `psql`, `pg_dump`, `pg_dumpall` | PostgreSQL | opzionale |
| `docker.io`, `podman`, `flatpak` | `docker`, `podman`, `flatpak` | container, app Flatpak | opzionale |
| `sudo` | `sudo` | Podman di un utente diverso da root (`v_podman_user`) | opzionale |

`./ndm_linux-backup.sh --requirements` (senza root) elenca gli strumenti richiesti dalle
tue impostazioni, quelli mancanti e il comando `apt-get` per installarli.
`sudo ./ndm_linux-backup.sh --analyze` mostra, per le tue impostazioni e questa
macchina, quali parti verrebbero eseguite e quali sono bloccate (vedi
[Analisi](#analisi)).

## Installazione

```bash
sudo apt install git
mkdir -p ~/bin && cd ~/bin
git clone https://github.com/nidamanx/NDM_Linux-Backup.git
cd NDM_Linux-Backup
chmod +x ndm_linux-backup.sh
sudo ./ndm_linux-backup.sh --analyze      # cosa farebbero le impostazioni attuali; non scrive nulla
```

Facoltativo: rendilo disponibile ovunque con un collegamento simbolico. Lo script trova
comunque `ndm_linux-backup.conf` e la sua cartella `backup/` accanto alla sua posizione
reale.

```bash
sudo ln -s "$PWD/ndm_linux-backup.sh" /usr/local/bin/ndm_linux-backup
```

Gli esempi di questo README presumono che il clone sia in `~/bin/NDM_Linux-Backup`.

### Solo lo script

Scaricare solo
[`ndm_linux-backup.sh`](https://raw.githubusercontent.com/nidamanx/NDM_Linux-Backup/main/ndm_linux-backup.sh)
basta per tutto, incluse le impostazioni per singola macchina (vedi
[Configurazione](#configurazione): non serve nessun file in più). L'unica eccezione è
`v_enable_mysql`/`v_enable_postgresql`, che richiedono rispettivamente
`my.cnf.example`/`pgpass.example`: in quel caso clona l'intero progetto.

### Aggiornamento

```bash
cd ~/bin/NDM_Linux-Backup
git pull --ff-only
./ndm_linux-backup.sh --version
```

L'aggiornamento non tocca mai il tuo `ndm_linux-backup.conf`, i file delle credenziali
né gli archivi in `backup/`: non fanno parte del repository. Tieni le tue impostazioni
in `ndm_linux-backup.conf` invece di modificare la sezione CONFIGURE dello script, così
`git pull` non va mai in conflitto con esse.

Se hai scaricato solo lo script, scarica quello nuovo dall'[ultima
release](https://github.com/nidamanx/NDM_Linux-Backup/releases/latest) e sostituisci il
vecchio file.

**Aggiornamento dalla 2.x** (pubblicata come *NDM Backup* su GitLab):

1. rinomina `ndm_backup.conf` in `ndm_linux-backup.conf`;
2. al suo interno, scrivi percorsi completi invece di `${HOME}` e togli tutto ciò che
   non è un'impostazione `KEY=value`: il file ora viene solo letto, mai eseguito (vedi
   [File di impostazioni esterno](#file-di-impostazioni-esterno)). `--requirements`
   indica la prima riga da correggere, se ce n'è una;
3. se usavi `v_datetime_suffix`, usa invece `v_datetime_format` (un formato di `date`);
   gli archivi ora si chiamano `ndm_linux-backup_<host>_...` e vengono preparati sotto
   `/home/ndm_linux-backup/`: imposta `v_backup_name=NDM_BK` per tenere i vecchi nomi (e
   la retention dei vecchi archivi), cancella la vecchia `/home/ndm_backup/` e usa
   `NDM_ARCHIVE_PREFIX` invece di `NDM_BACKUP_NAME` nei tuoi comandi hook;
4. aggiorna il percorso dello script nel collegamento simbolico e nel crontab.

Vedi [CHANGELOG.md](CHANGELOG.md) per tutte le modifiche.

## Utilizzo

```bash
./ndm_linux-backup.sh --requirements          # gli strumenti richiesti dalle impostazioni (senza root)
sudo ./ndm_linux-backup.sh --analyze          # cosa verrebbe salvato; non scrive nulla
sudo ./ndm_linux-backup.sh --start --dry-run  # simula un run completo; non scrive nulla
sudo ./ndm_linux-backup.sh --start            # esegue il backup
sudo ./ndm_linux-backup.sh --start --secrets  # anche l'archivio secrets, solo per questo run
```

Questo script richiede privilegi root per salvare la maggior parte delle parti della tua
macchina GNU/Linux:

`sudo ndm_linux-backup --start` oppure `su -c 'ndm_linux-backup --start'`

Prima di un run reale, puoi testare la tua configurazione in sicurezza con
`sudo ndm_linux-backup --start --dry-run` (vedi [Sicurezza](#sicurezza)), oppure
ottenere un resoconto istantaneo di cosa farebbero davvero le tue impostazioni attuali
con `sudo ndm_linux-backup --analyze` (vedi [Analisi](#analisi)).

| Flag | Forma estesa | Significato |
|---|---|---|
| `-s` | `--start` | avvia il backup |
| `-a` | `--analyze` | riporta cosa verrebbe salvato, saltato, o bloccato, poi esce -- vedi [Analisi](#analisi) |
| `-n` | `--dry-run` | simula ogni passo; non scrive nulla da nessuna parte |
| `-q` | `--quiet` | non fa domande e non mostra nessun progresso |
| `-k` | `--keep` | non elimina la directory temporanea dopo un run silenzioso |
|  | `--secrets` | produce anche l'archivio secrets per questo run, anche se `v_enable_secrets_backup=false` in CONFIGURE (non lo disattiva se è già `true`; vedi [Backup dei segreti](#backup-dei-segreti)) |
| `-h` | `--help` | mostra l'aiuto completo |
|  | `--requirements` | mostra gli strumenti richiesti dalle tue impostazioni, quelli mancanti e come installarli (senza root) |
| `-u` | `--usage` | mostra un messaggio d'uso breve |
| `-v` | `--version` | mostra la versione del software |

Le forme brevi ed estese sono intercambiabili e possono essere combinate, es.
`ndm_linux-backup -s -q -k` oppure `ndm_linux-backup -sqk`.

Aiuto completo: `ndm_linux-backup -h` oppure `ndm_linux-backup --help`.

## Configurazione

Tutti i parametri vivono nella sezione CONFIGURE in cima a `ndm_linux-backup.sh`. Puoi
modificarli direttamente lì, oppure sovrascrivere uno qualunque di essi da
`ndm_linux-backup.conf` (vedi [File di impostazioni
esterno](#file-di-impostazioni-esterno)) così i futuri aggiornamenti dello script non
cancellano le tue impostazioni per macchina. I più rilevanti:

- `v_dest` / `v_tempdir` / `v_dest_rsync`: dove viene scritto l'archivio, la directory
  di lavoro temporanea usata durante la raccolta dati, e una destinazione rsync
  opzionale; imposta `v_enable_rsync=false` per saltare il passo rsync senza svuotare
  `v_dest_rsync`. La sincronizzazione copia `v_dest` stesso (senza slash finale) dentro
  `v_dest_rsync`, quindi gli archivi finiscono annidati un livello più sotto, es.
  `v_dest_rsync/backup/*.tar.xz` con la configurazione di serie, non appiattiti in
  `v_dest_rsync/*.tar.xz` -- comportamento standard di rsync, non un bug, ma facile
  assumere il contrario. `v_tempdir` di default è
  `/home/ndm_linux-backup/${v_backup_name}` invece di `/tmp`: tutto ciò che l'archivio
  conterrà sta lì non protetto finché il `tar.xz` finale non esiste, così resta fuori da
  un percorso condiviso prevedibile e scrivibile da chiunque. `/home` invece di `/root`:
  entrambi sono di proprietà di root/non condivisi, ma `/root` sta comunemente sul
  filesystem di root (spesso piccolo), mentre `/home` è più spesso una propria
  partizione più grande -- rilevante dato che questa directory può contenere un intero
  albero di staging non compresso del passo data prima ancora di essere compresso. Non
  può stare di default sotto `/root`, `/etc`, o la directory dello script stesso in ogni
  caso: tutti e tre vengono già spazzati nell'archivio settings da `a_source_extra`, e
  `v_tempdir` è esso stesso una sorgente diretta di `tar`, non solo un percorso escluso
  come `v_dest` -- annidarlo dentro qualunque cosa `a_source_extra` spazzi duplica il
  suo contenuto nell'archivio oppure, se escluso per evitarlo, lo elimina dalla propria
  inclusione diretta. `v_tempdir_data`/`v_tempdir_secrets` sono suoi fratelli
  (`${v_backup_name}_data`/`${v_backup_name}_secrets`), quindi tutti e tre -- e solo
  questi -- vivono sotto un unico contenitore condiviso `/home/ndm_linux-backup` invece
  di disperdere directory separate al livello più alto. Quel contenitore viene validato
  e, la prima volta che serve, creato a `700` insieme a ciascuna foglia
  (`f_prepare_tempdir` in `main()`), così non finisce mai con i permessi più larghi che
  il suo primo creatore avesse lasciato:
  ```
  /home/ndm_linux-backup/        700 root:root  (contenitore, creato una volta, verificato a ogni run)
  ├── ndm_linux-backup/          700 root:root  (v_tempdir -- staging settings)
  │   ├── crontab.txt            600 root:root
  │   └── ...
  ├── ndm_linux-backup_data/     700 root:root  (v_tempdir_data -- solo se il passo data è attivo)
  │   └── ...
  └── ndm_linux-backup_secrets/  700 root:root  (v_tempdir_secrets -- solo se il passo secrets è attivo)
      └── files/
          └── etc/shadow         600 root:root
  ```
- `a_storage` / `a_luks`: quali dischi (es. `sda`, `nvme0n1`) e partizioni LUKS
  ispezionare. Imposta uno dei due a `( "auto" )` per auto-rilevare ogni disco fisico /
  partizione LUKS del sistema invece di elencarli a mano.
- `v_enable_*`: un interruttore on/off per ogni pezzo di backup (hardware, EFI, MBR,
  LUKS, LVM, partizioni, pacchetti installati, flatpak, AppImage, file di sistema
  modificati, file `/etc` non pacchettizzati, cron, MySQL, PostgreSQL, Docker, file
  Compose, Podman...). Imposta uno qualunque a `false` per saltare del tutto quel pezzo,
  senza toccare il resto dello script.
- `a_source_extra`: directory extra da includere nell'archivio così come sono (default:
  `/root`, `/etc`, `/usr/local/bin`, `/opt`, `/srv`, `/usr/local/etc`,
  `/var/spool/cron/crontabs`, e la directory propria dello script -- cattura come questa
  installazione di NDM Linux Backup stessa è configurata; `.git` e i file di credenziali
  MySQL/PostgreSQL sono esclusi dall'archivio anche se ricadono sotto uno di questi
  percorsi, vedi [Sicurezza](#sicurezza); i percorsi mancanti vengono saltati con un
  avviso invece di far fallire l'intero archivio); imposta `v_enable_source_extra=false`
  per saltarlo senza svuotare l'array.
- `a_appimages_extra_paths`: directory extra in cui cercare AppImage, in aggiunta ai
  default incorporati (`/home`, `/root`, `/opt`, `/usr/local/bin`).
- `a_docker_compose_extra_paths`: directory extra in cui cercare file Compose (Docker
  Compose / podman-compose), in aggiunta ai default incorporati (`/home`, `/root`,
  `/opt`, `/srv`).
- `v_mysql_cnf_path`: percorso del file di credenziali `.my.cnf` per i dump
  MySQL/MariaDB, default `${HOME}/.my.cnf`. Se manca, NDM Linux Backup prova prima
  l'auth via socket `root@localhost` prima di richiedere il file -- nessun interruttore
  separato, è solo un fallback (vedi [Backup MySQL/MariaDB](#backup-mysqlmariadb)).
- `v_postgresql_user` / `v_postgresql_pgpass_path`: utente con cui connettersi e
  percorso del file di credenziali `.pgpass` per i dump PostgreSQL, default
  `${HOME}/.pgpass` (vedi [Backup PostgreSQL](#backup-postgresql)). Se `.pgpass` manca,
  NDM Linux Backup prova prima l'auth locale peer/ident via socket Unix prima di
  richiedere il file -- nessun interruttore separato, è solo un fallback (vedi [Backup
  PostgreSQL](#backup-postgresql)).
- `v_podman_user`: l'istanza Podman rootless di quale utente ispezionare (di default lo
  stesso utente auto-rilevato di `v_dest`). Podman normalmente è rootless e per-utente,
  quindi leggerlo come root mostra solo lo stato proprio di root. Per un utente
  non-root, esegui `loginctl enable-linger <utente>` una volta (come root) così la sua
  directory di runtime esiste anche senza una sessione di login attiva.
- `v_pre_command` / `v_post_command`: tuoi comandi da eseguire prima/dopo il backup (es.
  fermare/avviare servizi, inviare una notifica); disattivati di default anche una volta
  impostati -- imposta anche `v_enable_pre_command` / `v_enable_post_command` a `true`
  per eseguirlo davvero. Entrambi ricevono
  `${NDM_HOSTNAME}`/`${NDM_ARCHIVE_PREFIX}`/`${NDM_LOG_PATH}`/`${NDM_USER}` (l'utente
  umano dietro `sudo`, come `v_username`) esportati da usare; `v_post_command` riceve in
  più `${NDM_EXIT_CODE}` (sempre `0` qui, vedi `v_on_failure_command` più sotto per i
  fallimenti) e, per ogni archivio davvero prodotto in questo run, il suo percorso
  completo e dimensione leggibile:
  `${NDM_SETTINGS_ARCHIVE}`/`${NDM_SETTINGS_ARCHIVE_SIZE}`,
  `${NDM_DATA_ARCHIVE}`/`${NDM_DATA_ARCHIVE_SIZE}`,
  `${NDM_SECRETS_ARCHIVE}`/`${NDM_SECRETS_ARCHIVE_SIZE}` -- vuoti per qualunque passo
  non girato in questa sessione. Vedi [Notifiche](#notifiche) per un esempio pronto
  all'uso con `ntfy` che copre entrambi.
- `v_on_failure_command`: un tuo comando da eseguire se il run fallisce (invia un'email,
  colpisci un webhook...) -- il vero punto dolente per l'uso non presidiato/via cron,
  dove un run fallito altrimenti compare solo nel log/exit code che nessuno sta
  guardando in diretta. Scatta da un unico trap `EXIT` che copre ogni uscita con errore
  dentro `main()` (dipendenza mancante, credenziali database mancanti, un passo tar/GPG
  fallito...) più Ctrl-C/SIGTERM, ma non i fallimenti prima che `main()` parta (un
  `ndm_linux-backup.conf` malformato, un flag CLI non valido) -- quelli sono problemi a
  tempo di configurazione che noteresti fin dal primissimo run.
  `${NDM_EXIT_CODE}`/`${NDM_LOG_PATH}`/`${NDM_ARCHIVE_PREFIX}`/`${NDM_HOSTNAME}`/`${NDM_USER}`
  sono esportati da usare; disattivato di default anche una volta impostato -- imposta
  anche `v_enable_on_failure_command=true` per eseguirlo davvero.
- `v_enable_data_backup` / `v_dest_data` / `v_tempdir_data`: attiva l'archivio data
  separato e dove viene scritto (vedi [Backup dei dati](#backup-dei-dati)).
- `v_enable_docker_volumes_data` / `v_enable_podman_volumes_data`: salva il contenuto
  reale dei volumi Docker/Podman, non solo l'elenco dei metadata.
- `a_data_source_extra`: directory extra con dati reali da includere nell'archivio data;
  disattivato di default anche una volta impostato -- imposta anche
  `v_enable_data_source_extra=true` per includerlo (richiede anche
  `v_enable_data_backup=true`, come gli altri interruttori del passo data).
- `v_enable_secrets_backup` / `v_dest_secrets` / `v_tempdir_secrets`: attiva l'archivio
  secrets separato e dove viene scritto (vedi [Backup dei
  segreti](#backup-dei-segreti)).
- `a_secrets_source` / `a_secrets_source_extra`: quali percorsi vengono spazzati
  nell'archivio secrets; il primo è un elenco curato incorporato (chiavi host SSH,
  `/etc/shadow`, credenziali di rete, credenziali proprie di root...), liberamente
  sovrascrivibile, il secondo è per qualunque cosa extra specifica della tua macchina.
- `v_enable_gpg_settings` / `_data` / `_secrets`: cifra con GPG l'archivio
  corrispondente, disattivato di default (vedi [Cifratura](#cifratura));
  `_data`/`_secrets` rispecchiano `v_enable_gpg_settings` a meno che non vengano
  sovrascritti indipendentemente. `v_gpg_recipient_file` / `_data` / `_secrets`:
  percorso della chiave pubblica destinataria di quell'archivio, default
  `${HOME}/pubkey.asc` per tutti e tre a meno che non venga sovrascritto.
- `v_tar_owner`: fa `chown` degli archivi settings/data verso l'utente che ha lanciato
  lo script subito dopo la creazione, default `true` (non contengono materiale segreto
  di default -- vedi [Sicurezza](#sicurezza)). `v_tar_owner_secrets`: uguale, ma per
  l'archivio secrets nello specifico, default `false` e deliberatamente indipendente --
  attivare `v_tar_owner` non consegna mai anche l'archivio secrets a un utente non-root;
  serve un proprio `true` esplicito.
- `v_datetime_format`: data e ora alla fine del nome di ogni archivio, checksum e log,
  come formato di `date`, default `%Y%m%d-%H%M%S` (ora locale). Ne possono uscire solo
  lettere, cifre, `.`, `_` e `-`; `%A` da solo dà un archivio per giorno della
  settimana, sovrascritto ogni settimana.

### File di impostazioni esterno

`ndm_linux-backup.conf`, accanto allo script (nella sua posizione reale, anche se
lanciato tramite un collegamento simbolico), sovrascrive la sezione CONFIGURE dello
script. È opzionale: senza di esso vengono usati i default incorporati, quindi un
singolo `ndm_linux-backup.sh` scaricato continua a funzionare da solo.

```bash
cd ~/bin/NDM_Linux-Backup
cp -n ndm_linux-backup.conf.example ndm_linux-backup.conf
editor ndm_linux-backup.conf
```

Tieni solo le righe che vuoi cambiare: una singola riga come `v_enable_mysql=true` è un
file valido. Il file viene solo letto, mai eseguito (vedi [Sicurezza](#sicurezza)):

```bash
v_enable_mysql=true                       # una riga KEY=value per impostazione, # inizia un commento
v_dest="/mnt/miei backup"                 # valori con spazi tra virgolette
v_gpg_recipient_file=/root/pubkey.asc     # percorsi completi: $HOME e $(...) non vengono espansi
a_luks=( "sda3" "nvme0n1p3" )             # liste
a_source_extra=(                          # liste su più righe: sostituiscono quella incorporata
  "/etc"
  "/srv/miei dati"
)
v_post_command='curl -fsS -d "Backup finito su ${NDM_HOSTNAME}" https://ntfy.sh/REPLACE_WITH_YOUR_OWN_RANDOM_TOPIC'
```

Solo i tre comandi hook (`v_pre_command`, `v_post_command`, `v_on_failure_command`)
possono contenere `$`: vengono tenuti come scritti ed eseguiti più tardi, come root,
dallo script (vedi [Notifiche](#notifiche)). Un'impostazione sconosciuta o un valore non
valido fermano lo script con codice di uscita 2 e indicano la riga sbagliata; `--help` e
`--version` funzionano comunque.

Non serve cambiare proprietario: `ndm_linux-backup.conf` resta tuo, come
`ndm_linux-backup.sh` stesso. Vedi [Sicurezza](#sicurezza) per bloccare opzionalmente
entrambi i file su una macchina condivisa, e la sezione CONFIGURE dello script per ogni
impostazione e il suo default.

### Backup MySQL/MariaDB

`v_mysql_cnf_path` di default è `${HOME}/.my.cnf` (di root, dato che lo script richiede
root) -- lo stesso file che i client `mysql`/`mysqldump` leggono automaticamente:

1. `sudo cp -n ~/bin/NDM_Linux-Backup/my.cnf.example /root/.my.cnf`
2. `sudo editor /root/.my.cnf` (imposta il tuo utente/password mysql sotto `[client]`)
3. `sudo chmod 600 /root/.my.cnf`

_Nota: puoi puntare `v_mysql_cnf_path` a una posizione personalizzata (es. una copia
tenuta accanto allo script). Se manca quando `v_enable_mysql=true` e `mysqldump` è
installato, NDM Linux Backup prova prima l'auth via socket `root@localhost` (vedi
sotto); solo se anche questo fallisce segnala il file mancante ed esce prima di fare
qualunque lavoro -- non crea o modifica mai questo file da solo. A differenza di
`ndm_linux-backup.conf`, non c'è un passo di ownership separato: questo file viene letto
solo come dato semplice (mai sorgentato/eseguito), quindi root lo legge bene a
prescindere da chi lo possieda -- il `sudo cp` sopra lo rende comunque già di root fin
dall'inizio. `my.cnf.example` stesso documenta tutto questo inline, come commenti `#` (i
file di opzioni MySQL li supportano)._

_Evitare del tutto una password/file -- l'account `root@localhost` di default di Debian
di solito lo permette già:_

1. Verifica: `sudo mysql --no-defaults -u root -e "SELECT 1"` -- stampa `1` senza
   chiedere la password? Già impostato, salta del tutto `.my.cnf`.
2. Chiede ancora una password? Controlla il plugin:
   `sudo mysql -e "SELECT user, plugin FROM mysql.user WHERE user='root';"` --
   `unix_socket`/`auth_socket` è quello senza password; passa a quello se è
   qualcos'altro.

`.my.cnf`, se presente, ha sempre la precedenza. Se manca, NDM Linux Backup esegue da
solo il passo 1 automaticamente (con un limite di tempo, così un server irraggiungibile
non può bloccare un run non presidiato) e usa `--no-defaults -u root` al suo posto.

### Backup PostgreSQL

`v_postgresql_pgpass_path` di default è `${HOME}/.pgpass` (di root) -- lo stesso file
che i client PostgreSQL leggono automaticamente:

1. `sudo cp -n ~/bin/NDM_Linux-Backup/pgpass.example /root/.pgpass`
2. `sudo editor /root/.pgpass` (imposta host:porta:database:utente:password, es.
   `localhost:5432:*:postgres:secret`)
3. `sudo chmod 600 /root/.pgpass`

_Nota: i client PostgreSQL ignorano silenziosamente .pgpass se non è chmod 600. Puoi
puntare `v_postgresql_pgpass_path` a una posizione personalizzata; imposta anche
`v_postgresql_user` in CONFIGURE se non corrisponde all'utente in .pgpass. Come sopra:
NDM Linux Backup controlla solo che il file esista e ti dice come crearlo se non c'è,
non lo crea o modifica mai da solo, e non c'è nemmeno un passo di ownership separato,
stesso ragionamento di `.my.cnf` sopra. `pgpass.example` stesso documenta tutto questo
inline, come commenti `#` (PostgreSQL salta le righe che iniziano con `#`, come le righe
vuote)._

_Evitare del tutto una password/file -- a differenza di MySQL, questo richiede una
configurazione: il nome del ruolo PostgreSQL deve corrispondere esattamente all'utente
del sistema operativo che si connette, e questo script gira sempre come `root`, non come
`postgres`:_

1. `pg_hba.conf` (es. `/etc/postgresql/<versione>/main/pg_hba.conf`), la riga `local`
   per il ruolo in `v_postgresql_user`:
   `local   all   postgres   peer map=ndm_linux-backup`
2. `pg_ident.conf`: `ndm_linux-backup   root   postgres` (mappa l'utente OS `root` sul
   ruolo PostgreSQL `postgres`)
3. `sudo systemctl reload postgresql`
4. Verifica: `sudo psql -U postgres -tAc "SELECT 1"` -- stampa `1` senza chiedere la
   password? Fatto, salta del tutto `.pgpass`.

`.pgpass`, se presente, ha sempre la precedenza. Se manca, NDM Linux Backup esegue da
solo il controllo del punto 4 automaticamente (con un limite di tempo, così un server
irraggiungibile non può bloccare un run non presidiato) e ricade sul richiedere
`.pgpass` se fallisce.

## Notifiche

NDM Linux Backup non ha una propria funzione di notifica -- riusa
`v_pre_command`/`v_post_command`/ `v_on_failure_command` (vedi
[Configurazione](#configurazione)), ciascuno semplicemente una stringa di comando
arbitraria, eseguita con `eval` con un pugno di variabili `NDM_*` esportate da usare.
Qualunque servizio push raggiungibile con una singola chiamata `curl` funziona allo
stesso modo; [ntfy](https://ntfy.sh) (semplice, self-hostable) è usato come esempio qui
sotto.

> [!WARNING]
> Un topic `ntfy.sh` non riservato è pubblico: chiunque ne conosca o indovini il nome
> può leggerlo. Scegli un nome di topic lungo e casuale (o fai self-hosting) invece del
> placeholder qui sotto.

Conserva qualunque token di accesso allo stesso modo in cui vengono conservati
`.my.cnf`/`.pgpass` -- in un proprio file leggibile solo da root, mai inline dentro
`v_pre_command`/`v_post_command`/`v_on_failure_command` stessi (quelli vivono in
CONFIGURE, o in `ndm_linux-backup.conf`, e finiscono nell'archivio settings di questa
stessa macchina tramite `a_source_extra`):
```
echo 'tk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' > ${HOME}/.ntfy_token
chmod 600 ${HOME}/.ntfy_token
```

```bash
v_enable_pre_command=true
v_pre_command='curl -fsS -H "Authorization: Bearer $(cat ${HOME}/.ntfy_token)" -H "Title: NDM Linux Backup" -d "$(date "+%F %T") - Starting backup ${NDM_USER}@${NDM_HOSTNAME}" https://ntfy.sh/REPLACE_WITH_YOUR_OWN_RANDOM_TOPIC'

v_enable_post_command=true
v_post_command='curl -fsS -H "Authorization: Bearer $(cat ${HOME}/.ntfy_token)" -H "Title: NDM Linux Backup" -d "$(date "+%F %T") - Backup done ${NDM_USER}@${NDM_HOSTNAME}: settings ${NDM_SETTINGS_ARCHIVE_SIZE}${NDM_DATA_ARCHIVE:+, data ${NDM_DATA_ARCHIVE_SIZE}}${NDM_SECRETS_ARCHIVE:+, secrets ${NDM_SECRETS_ARCHIVE_SIZE}}" https://ntfy.sh/REPLACE_WITH_YOUR_OWN_RANDOM_TOPIC'

v_enable_on_failure_command=true
v_on_failure_command='curl -fsS -H "Authorization: Bearer $(cat ${HOME}/.ntfy_token)" -H "Title: NDM Linux Backup FAILED" -H "Priority: urgent" -d "NDM Linux Backup failed on ${NDM_USER}@${NDM_HOSTNAME} (exit ${NDM_EXIT_CODE}) -- see ${NDM_LOG_PATH}" https://ntfy.sh/REPLACE_WITH_YOUR_OWN_RANDOM_TOPIC'
```

Tutti e tre usano apici singoli: nella sezione CONFIGURE dello script tengono `${NDM_*}`
non espanso finché `eval` non esegue ogni comando al suo effettivo momento di
attivazione; in `ndm_linux-backup.conf` comunque nulla viene espanso in lettura, quindi
le stesse righe funzionano lì così come sono. L'esempio di `v_post_command` sopra salta
del tutto la clausola `, data ...`/`, secrets ...` ogni volta che quell'archivio non è
girato in questa sessione (`${NDM_DATA_ARCHIVE:+...}` -- vuoto a meno che
`NDM_DATA_ARCHIVE` non sia impostato), così la stessa riga funziona invariata sia che tu
abbia i passi data/secrets attivi o no.

## Cron

`--quiet` (`-q`) è ciò che rende possibile un run non presidiato: salta ogni richiesta
di conferma (se eseguire del tutto, se riusare una directory di lavoro esistente, se
eliminarla dopo -- vedi [Sicurezza](#sicurezza) e [Utilizzo](#utilizzo)), così l'intero
run non richiede alcuna interazione, dall'inizio alla fine. Verificato dal vivo:
`--start --quiet` con stdin chiuso (`< /dev/null`, esattamente come cron stesso esegue
un job) completa ed esce con `0` senza mai toccare stdin.

Esempio, eseguito ogni giorno alle 3:00 come root:
```
0 3 * * * /usr/local/bin/ndm_linux-backup --start --quiet
```
Modifica il crontab di root con `sudo crontab -e` (quello proprio di root, dato che lo
script richiede root -- vedi [Utilizzo](#utilizzo)). Punti da tenere a mente:
- Senza `--keep` (`-k`), la directory di lavoro (`v_tempdir`) viene eliminata
  automaticamente dopo un run silenzioso, come rispondere "sì" al prompt interattivo --
  nulla resta tra un run e l'altro.
- cron manda per email a `MAILTO` (o al proprietario del crontab) l'stdout/stderr di un
  job per default, in aggiunta al file `.log` del run già scritto nella destinazione del
  backup (vedi [Sicurezza](#sicurezza), "Log del run" -- quello è completo e
  incondizionato indipendentemente da `--quiet`). Se non vuoi entrambi, reindirizza
  invece la copia propria di cron:
  `... --start --quiet >> /var/log/ndm_linux-backup_cron.log 2>&1`.
- Un run fallito compare solo nel log/exit code per default, cosa che nessuno sta
  guardando in diretta in una configurazione non presidiata -- è esattamente il caso per
  cui esiste `v_on_failure_command` (vedi [Configurazione](#configurazione) e
  [Notifiche](#notifiche)): impostalo una volta e ottieni una notifica reale (email,
  push, webhook) invece di scoprirlo giorni dopo.
- Il `PATH` proprio di cron è minimale (nessun profilo di shell viene sorgentato),
  quindi usa il percorso completo dello script nella riga di crontab, non solo
  `ndm_linux-backup`, anche se l'hai simlinkato nel tuo `PATH` normale (vedi
  [Installazione](#installazione)).

## Analisi

`sudo ndm_linux-backup --analyze` riporta, per le tue impostazioni attuali in CONFIGURE,
quali moduli verranno davvero salvati, quali sono attivi ma bloccati da qualcosa (un
tool mancante, un `.my.cnf`/`.pgpass` mancante, nessuna partizione LUKS trovata,
`v_dest_rsync` non impostato...), quali sono semplicemente disattivati ma
funzionerebbero se attivati, e quali sono disattivati *e* sarebbero comunque bloccati
anche se attivati perché questa macchina non ha l'hardware/firmware corrispondente
(nessun UEFI, nessun disco partizionato MBR, nessuna partizione LUKS, nessun LVM) -- poi
esce. Raggruppato in una sezione per archivio (settings/data/secrets) più una
trasversale per rsync/hook, così è chiaro a colpo d'occhio cosa conterrebbe davvero
ciascun archivio. La sezione di ciascun archivio dichiara anche la propria directory di
lavoro (`v_tempdir`/`_data`/`_secrets` -- dove l'archivio viene preparato prima di
`tar`) e la propria destinazione (`v_dest`/`_data`/`_secrets` -- dove finisce il
`.tar.xz` finale), così puoi confermare i percorsi che userebbe un run reale prima che
li usi davvero. A differenza di `--dry-run`, non esegue mai un solo comando di backup
reale (nessun `lshw`, nessun dump di schema, niente): controlla solo l'applicabilità e
stampa i percorsi già configurati, senza crearli o toccarli -- nessun `v_tempdir`,
nessun `v_dest`, nessun file di log viene davvero scritto o creato, quindi è quasi
istantaneo e non legge/scrive nulla oltre al controllo stesso, indipendentemente da
`--quiet`/`--keep`/`--dry-run` (tutti irrilevanti per esso) o dal fatto che sia
combinato con `--start` (`--analyze` vince sempre e nessun backup gira). `--secrets`
viene rispettato, così riflette se l'archivio secrets verrebbe davvero prodotto per quel
run, e riporta anche quali degli archivi che verranno davvero prodotti finiscono cifrati
con GPG o restano in chiaro -- lo stesso controllo che fa un run reale, vedi
[Cifratura](#cifratura).

> [!NOTE]
> La verifica delle credenziali MySQL/PostgreSQL è un'eccezione a "nessun comando reale
> gira mai": `--analyze` non tenta mai la connessione live via socket/peer-auth
> `root@localhost` che fa un vero `--start` (vedi Backup MySQL/MariaDB e [Backup
> PostgreSQL](#backup-postgresql)), quindi può riportare `.my.cnf`/`.pgpass` come
> mancanti anche su una macchina dove un run reale riuscirebbe comunque tramite quel
> fallback. Il motivo riportato nomina sempre il fallback così questo non si legge come
> un blocco definitivo.

## Ripristino

Non esiste deliberatamente un unico comando "ripristina tutto". NDM Linux Backup
raccoglie; rimettere le cose a posto su una macchina reale è ogni volta una scelta di
giudizio (disco corrispondente, versioni dei pacchetti corrispondenti, se la
destinazione è addirittura la stessa macchina) che non dovrebbe essere automatizzata
alla cieca. Ripristinare significa: estrarre l'archivio che serve, leggere cosa c'è
dentro, applicare a mano il singolo pezzo di cui hai davvero bisogno.

Prima di fidarti di un vecchio archivio, verificalo contro il suo file di checksum (vedi
[Sicurezza](#sicurezza)) -- contro qualunque file sia realmente su disco, `.tar.xz` o
`.tar.xz.gpg` se la cifratura è attiva, dato che il checksum copre l'artefatto finale,
non necessariamente il testo in chiaro:
```
sha256sum -c ndm_linux-backup_myhost_20260815-120000.tar.xz.sha256
```

**Se l'archivio è cifrato** (il nome file finisce in `.tar.xz.gpg`, vedi
[Cifratura](#cifratura)), decifralo prima, sulla macchina da cui stai davvero facendo il
ripristino -- la chiave privata non serviva deliberatamente mai sulla macchina di backup
stessa:
```
gpg --output ndm_linux-backup_myhost_20260815-120000.tar.xz --decrypt ndm_linux-backup_myhost_20260815-120000.tar.xz.gpg
```
Funziona così com'è se la chiave privata corrispondente è già nel tuo portachiavi
(`gpg --list-secret-keys`). Se non lo è -- conservata invece in un file, o su una
chiavetta USB rimovibile, apposta perché non stia mai su una macchina normalmente
connessa -- importala in un portachiavi isolato e usa e getta solo per questa operazione
invece di unirla al tuo `~/.gnupg` di tutti i giorni:
```
export GNUPGHOME="$(mktemp -d)"
gpg --import /media/usb/ndm-linux-backup-private-key.asc
gpg --output ndm_linux-backup_myhost_20260815-120000.tar.xz --decrypt ndm_linux-backup_myhost_20260815-120000.tar.xz.gpg
rm -rf "${GNUPGHOME}"
unset GNUPGHOME
```
Il `rm -rf "${GNUPGHOME}"` finale scarta il portachiavi temporaneo (e la chiave privata
importata con esso) -- la chiavetta USB o il file chiave restano l'unica copia
permanente, esattamente lo scopo di tenerla offline fin dall'inizio.

Ogni archivio si estrae in una cartella chiamata come se stesso:
```
tar -xJf ndm_linux-backup_myhost_20260815-120000.tar.xz -C /percorso/di/estrazione
```

Ogni percorso qui sotto (`software/`, `modified_files/`, `partitions/`, `mbr/`,
`grub/`...) è relativo a `v_tempdir` dentro quella cartella -- di default
`home/ndm_linux-backup/ndm_linux-backup/`, dato che `v_tempdir` è un percorso assoluto e
tar lo ricrea per intero. Il vero resoconto vive lì; `etc/`, `root/`, `opt/`... al
livello più alto è la scansione grezza di `a_source_extra`, non il resoconto stesso.

### Archivio settings

<details>
<summary>Riferimento di ripristino per singolo elemento (clicca per espandere)</summary>

- **Pacchetti** (`software/apt_manual.txt`, `apt_auto.txt`): reinstalla con
  `sudo apt-get install $(cat apt_manual.txt)`. Questo ripristina solo i *nomi* dei
  pacchetti, non le versioni fissate -- va bene dopo una reinstallazione pulita della
  stessa release Debian, non è una garanzia di versioni dei pacchetti identiche byte per
  byte.
- **File modificati/non pacchettizzati** (`modified_files/`, `unpackaged_files/`,
  entrambi che rispecchiano il vero layout di `/etc`): esamina ogni file e copialo
  indietro individualmente (`diff` contro il file live prima). Non estrarre mai questo
  albero direttamente sopra un `/etc` live -- è stato catturato in un momento preciso e
  può entrare in conflitto con modifiche fatte da allora.
  **`unpackaged_files/etc/machine-id`** nello specifico: ripristina questo solo sulla
  *stessa* macchina da cui l'hai preso (es. dopo una reinstallazione pulita) --
  `/etc/machine-id` è pensato per essere globalmente unico per ogni installazione,
  quindi copiarlo su una macchina *diversa* può confondere D-Bus, systemd-journal, e gli
  identificatori client DHCP derivati da esso.
- **Tabella delle partizioni** (`partitions/sfdisk_<disco>.txt`):
  `sfdisk /dev/<disco> < sfdisk_<disco>.txt` ricrea il layout delle partizioni --
  **distruttivo**, e ha senso solo su un disco della stessa dimensione/geometria
  dell'originale. `partitions/fdisk_<disco>.txt` è la controparte leggibile, solo di
  consultazione.
- **MBR/settore di avvio** (`mbr/<disco>_mbr.bin`):
  `dd if=<disco>_mbr.bin of=/dev/<disco> bs=1M count=1` -- stessa avvertenza, solo sul
  disco esatto giusto, solo se capisci che questo sovrascrive l'attuale settore di
  avvio.
- **UEFI** (`efi/efibootmgr.txt`, `efi/boot_efi/`): `efibootmgr.txt` è solo di
  consultazione, ricrea a mano le voci di avvio NVRAM con `efibootmgr --create` se
  serve. `boot_efi/` è una copia reale del contenuto della EFI System Partition e può
  essere copiata indietro (`cp -a boot_efi/. /boot/efi/`) -- **solo sullo stesso
  identico sistema UEFI o su uno partizionato in modo equivalente**, dopo aver montato
  tu stesso la vera ESP, mai indovinando il mountpoint. Sbagliare questo su una ESP live
  può lasciare il sistema incapace di avviarsi.
- **LUKS** (`luks/luksDump_<disco>.txt`, `luksUUID_<disco>.txt`, `crypttab.txt`): solo
  di consultazione, **non** un backup dell'header ripristinabile -- questo è l'output
  testuale leggibile di `cryptsetup luksDump`, non un dump binario raw di
  `luksHeaderBackup`. Se un header LUKS si corrompe davvero, questo ti dice la
  cifra/disposizione dei keyslot per ricreare a mano un container equivalente, ma non
  può ricostruire l'header/i keyslot originali byte per byte. Per quello, vedi il backup
  raw dell'header LUKS nell'archivio secrets più sotto.
- **LVM** (`lvm/pvdisplay.txt`, `vgdisplay.txt`, `lvdisplay.txt`, `lvmdump/`): solo di
  consultazione, **non** un backup ripristinabile nemmeno questo -- output leggibile di
  `pvdisplay`/`vgdisplay`/`lvdisplay` più un bundle diagnostico `lvmdump`, non metadati
  raw. Usali per ricreare a mano il layout PV/VG/LV (`pvcreate`/`vgcreate`/`lvcreate`
  che corrispondano ai nomi/dimensioni registrati) su un disco nuovo; a differenza di
  LUKS, per questo non esiste un'opzione di backup dei metadati raw.
- **Grub** (`grub/boot_grub/`, `grub/default_grub.txt`): copia `boot_grub/` indietro in
  `/boot/grub` e `default_grub.txt` in `/etc/default/grub`, poi esegui `update-grub` --
  preferisci rigenerare piuttosto che fidarti ciecamente dei file copiati se le versioni
  del kernel differiscono dall'originale. `grub-install /dev/<disco>` solo se anche il
  settore di avvio stesso deve essere reinstallato, **solo sullo stesso disco o su uno
  equivalente**: una combinazione disco/versione sbagliata può lasciare il sistema
  incapace di avviarsi.
- **Schema MySQL/PostgreSQL** (`mysql_schema/schema_<db>.sql` o `schema_all.sql`;
  `postgresql_schema/schema_<db>.sql`/`schema_all.sql`):
  `mysql --defaults-file=.my.cnf < schema_db.sql` / `psql -f schema_db.sql nomedb`
  ricrea la struttura (tabelle/viste/trigger/routine), nessuna riga. Ripristina lo
  schema *prima* dei dati (vedi archivio data più sotto) -- il ripristino dei dati
  assume che le tabelle esistano già.
- **Docker/Podman** (`docker/`, `podman/`, `docker_compose_files/`): i file di metadata
  sono solo di consultazione; il recupero reale è `docker compose up -d` (o
  `podman-compose`/Quadlet) a partire dai file compose/unit copiati, che scarica
  immagini fresche dal registry -- le immagini/container stessi non sono mai stati
  salvati, vedi [Cosa viene salvato](#cosa-viene-salvato).
- **Crontab** (`crontab.txt`): `crontab crontab.txt` ripristina la pianificazione di
  root. Rischio basso -- esamina prima il file se fa riferimento a percorsi che
  potrebbero non esistere più sulla destinazione.
- **Flatpak** (`flatpak.txt`): solo di consultazione, reinstalla le app elencate con
  `flatpak install <app-id>`.
- **Directory di `a_source_extra`**: copiate così come sono sotto il proprio percorso
  dentro l'archivio, ripristina copiandole indietro nella loro posizione originale. Vale
  la stessa cautela dei file modificati/non pacchettizzati sopra se una di esse ricade
  sotto `/etc` o `/root`: esamina prima di estrarre sopra un sistema live.

</details>

### Archivio data

Come l'archivio settings sopra: ogni percorso qui sotto è relativo a `v_tempdir_data`
dentro la cartella estratta -- di default
`home/ndm_linux-backup/ndm_linux-backup_data/`.

<details>
<summary>Riferimento di ripristino per singolo elemento (clicca per espandere)</summary>

- **Righe dei dati MySQL/PostgreSQL** (`mysql/data_<db>.sql` o `data_all.sql`;
  `postgresql/data_<db>.sql`/ `data_all.sql`): importa *dopo* che lo schema
  corrispondente esiste (dall'archivio settings, o ricreato a mano):
  `mysql --defaults-file=.my.cnf nomedb < data_db.sql` / `psql -f data_db.sql nomedb`.
- **Contenuto dei volumi Docker/Podman** (`docker_volumes/<nome>/`,
  `podman_volumes/<nome>/`): crea prima un volume nuovo e vuoto
  (`docker volume create <nome>`), trova il suo vero Mountpoint
  (`docker volume inspect <nome>`), poi copia dentro il contenuto salvato --
  `cp -a docker_volumes/<nome>/. <mountpoint>/`. Controlla proprietà/permessi dopo:
  devono corrispondere a ciò che il container si aspetta, cosa che `cp -a` da solo non
  garantisce se gli UID differiscono tra le macchine.
- **Directory di `a_data_source_extra`**: copiate così come sono, ripristina copiandole
  indietro nel loro percorso originale.

</details>

### Archivio secrets

`files/` stesso è relativo a `v_tempdir_secrets` dentro la cartella estratta -- di
default `home/ndm_linux-backup/ndm_linux-backup_secrets/files/`. Ogni voce al suo
interno mantiene il proprio percorso assoluto originale (es.
`files/etc/ssh/ssh_host_rsa_key`, `files/root/.ssh/id_ed25519`), quindi ripristinare un
elemento significa copiarlo indietro a quello stesso percorso e sistemare
proprietà/permessi (chiavi host SSH: `600 root:root`; `/etc/shadow`/`/etc/gshadow`:
`640 root:shadow`).

<details>
<summary>Riferimento di ripristino per singolo elemento (clicca per espandere)</summary>

- **Chiavi host SSH**: ripristinare la chiave *originale* (non rigenerarne una nuova)
  significa che i client che già si fidano dell'impronta di questa macchina non vedranno
  un avviso "REMOTE HOST IDENTIFICATION HAS CHANGED" dopo una reinstallazione -- spesso
  è proprio questo il motivo per ripristinarle nello specifico. `chmod 600`,
  `chown root:root`, riavvia `sshd`.
- **`/root/.ssh`** (chiavi proprie di root, distinte dalle chiavi host SSH sopra): `600`
  sulle chiavi private, `644` su `authorized_keys`/`known_hosts`, di proprietà di
  `root`. Ripristinare un vecchio `authorized_keys` può silenziosamente ripristinare
  l'accesso per una chiave che intendevi revocare -- esamina il contenuto prima di
  ripristinarlo, non copiarlo indietro alla cieca.
- **`/etc/shadow`/`/etc/gshadow`**: **non** estrarre questi sopra i file di un sistema
  live. Uno `/etc/shadow` malformato o non corrispondente può bloccare fuori ogni
  account o rompere PAM del tutto. Se ti serve indietro l'hash della password di un
  account specifico, ripristinalo chirurgicamente (es. `usermod -p '<hash>' nomeutente`)
  invece di sostituire l'intero file; sostituisci il file per intero solo da un contesto
  offline (media di ripristino/chroot), mai su un sistema in esecuzione.
- **Chiavi private TLS / Let's Encrypt / credenziali di rete / config CLI cloud**: copia
  indietro al percorso originale, riavvia il servizio che le usa.
- **Segreti mail relay / PPP** (`exim4/passwd.client`, `postfix/sasl_passwd`(`.db`),
  `ppp/chap-secrets`, `ppp/pap-secrets`): copia indietro al percorso originale, riavvia
  il servizio corrispondente. Per Postfix nello specifico, rigenera `sasl_passwd.db` dal
  file in chiaro con `postmap` invece di fidarti che il binario `.db` copiato
  corrisponda alla versione di Postfix della macchina di destinazione.
- **`/root/.gnupg`**: ripristinare questo su un portachiavi che ha già altre chiavi può
  produrre impostazioni di trust duplicate o in conflitto. Ripristina su un
  `/root/.gnupg` nuovo, oppure `gpg --import` solo la chiave specifica che ti serve,
  invece di sovrascrivere un portachiavi in uso.
- **`/root/.docker/config.json`**: copia indietro per ripristinare i login salvati sui
  registry. Contiene credenziali del registry (in chiaro o codificate in base64 a
  seconda del registry) -- maneggia il file estratto con la stessa cura del resto di
  questo archivio.
- **`.my.cnf`/`.pgpass`** (le credenziali database proprie di questo script): copia
  indietro in `v_mysql_cnf_path`/`v_postgresql_pgpass_path`, `600 root:root`. Utile solo
  se host/utente del database sulla macchina di destinazione corrispondono a ciò che c'è
  dentro -- altrimenti NDM Linux Backup semplicemente non riesce a connettersi al run
  successivo, come un file di credenziali mancante (vedi [Sicurezza](#sicurezza)).
- **`/etc/mysql/debian.cnf`**: credenziali di manutenzione interna proprie di
  MariaDB/MySQL, copia indietro alla lettera -- non modificarlo, gli script di
  manutenzione dei pacchetti (`logrotate`, `mysql_upgrade`...) si aspettano il suo
  contenuto originale esatto.
- **`/root/.netrc`**: credenziali di auto-login in chiaro per qualunque tool lo legga
  (`curl`, `ftp`...), copia indietro con `600 root:root` -- stessa gestione di qualunque
  altro file di credenziali in chiaro in questo archivio.
- **Header LUKS raw** (`luks_headers/<disco>_luksHeaderBackup.img`, presente solo se
  `v_enable_luks_header_backup=true`):
  `cryptsetup luksHeaderRestore /dev/<disco> --header-backup-file <disco>_luksHeaderBackup.img`
  lo riscrive indietro -- **solo quando sei certo che la destinazione sia davvero lo
  stesso volume** (UUID corrispondente, verificato con `cryptsetup luksUUID`);
  ripristinare un header sul dispositivo sbagliato lo rende illeggibile, non fallisce
  semplicemente in modo sicuro.

</details>

> [!WARNING]
> Indipendentemente da quale archivio: non estrarne mai nessuno direttamente sulla `/`
> di un sistema live. Estrai prima in una directory usa e getta, esamina ciò di cui hai
> davvero bisogno, poi applicalo a mano.

## Esempio di output

`sudo ./ndm_linux-backup.sh --analyze` su una piccola macchina virtuale Debian 13 (BIOS,
un disco, niente LUKS né LVM) con le impostazioni di default; nome host e percorsi sono
generici:

```
Your system is based on: bios
Your partition type for /dev/vda is: dos

NDM Linux Backup 3.0.1 -- analysis for root@myhost (run --start to actually back up)

=== SETTINGS ARCHIVE (always produced) ===
Working directory (src): /home/ndm_linux-backup/ndm_linux-backup
Destination (dest): /home/user/bin/NDM_Linux-Backup/backup
Enabled: hardware, devices, lsblk, blkid, inxi, mbr, os_release, kernel, partitions, grub, packages, modified_files, unpackaged_files, cron, source_extra
Enabled but blocked:
  efi                  -- not a UEFI system
Disabled (could enable in the settings): flatpak, appimages, mysql, postgresql, docker, docker_compose, podman
Not applicable to this machine:
  luks                 -- no LUKS partitions found
  lvm                  -- no LVM volumes detected

=== DATA ARCHIVE (opt-in) ===
Working directory (src): /home/ndm_linux-backup/ndm_linux-backup_data
Destination (dest): /home/user/bin/NDM_Linux-Backup/backup
Master switch (v_enable_data_backup): disabled
Enabled: (none)
Disabled (could enable in the settings): docker_volumes_data, podman_volumes_data, data_source_extra

=== SECRETS ARCHIVE (opt-in) ===
Working directory (src): /home/ndm_linux-backup/ndm_linux-backup_secrets
Destination (dest): /home/user/bin/NDM_Linux-Backup/backup
Master switch (v_enable_secrets_backup): disabled (pass --secrets to include it for this run)
Enabled: (none)
Not applicable to this machine:
  luks_header_backup   -- no LUKS partitions found

=== OTHER (cross-cutting) ===
Enabled: (none)
Disabled (could enable in the settings): rsync, pre_command, post_command, on_failure_command
```

Ogni archivio ha la sua sezione: cosa verrà salvato, cosa è attivo ma non può girare su
questa macchina (e perché), cosa è disattivato e cosa questa macchina non ha. Non viene
scritto nulla e non gira nessun comando di backup (vedi [Analisi](#analisi)).

## Servizi esterni contattati

Nessuno di suo: un run di backup funziona offline e non invia nulla. La rete viene usata
solo da ciò che scegli di attivare:

| Servizio | Quando | Cosa riceve |
|----------|--------|-------------|
| Mirror dei pacchetti Debian (`apt-get`) | Solo se accetti di installare gli strumenti mancanti | Le normali richieste dei pacchetti |
| La tua destinazione `v_dest_rsync` | Solo con `v_enable_rsync=true` e una destinazione remota | Gli archivi |
| I tuoi server di database | Solo con MySQL/MariaDB o PostgreSQL attivi (di solito `localhost`) | Le credenziali di `.my.cnf`/`.pgpass` |
| Ciò che chiamano i tuoi comandi hook | Solo con `v_pre_command`/`v_post_command`/`v_on_failure_command` attivi (vedi [Notifiche](#notifiche)) | Ciò che metti nel comando |

`--analyze`, `--dry-run`, `--requirements`, `--help`, `--usage` e `--version` non
contattano nulla.

## Codici di uscita

| Codice | Significato |
|:------:|-------------|
| `0` | Backup completato; anche `--analyze`, `--requirements`, `--help`, `--usage`, `--version`, nessun argomento, e una domanda a cui hai risposto *No* o *Cancel* |
| `1` | Un errore: non eseguito come root, strumento obbligatorio mancante, credenziali del database o chiave GPG mancanti, cartella di lavoro non sicura, creazione o cifratura di un archivio fallita |
| `2` | Uso non valido della riga di comando (opzione sconosciuta, argomento inatteso, `-n`/`-q`/`-k`/`--secrets` senza `--start` o `--analyze`), o un'impostazione non valida in `ndm_linux-backup.conf` |
| `130` | Interrotto (Ctrl-C): i file già raccolti restano per il run successivo |
| `143` | Terminato (SIGTERM): idem |

Per i run non presidiati, `v_on_failure_command` segnala gli errori quando avvengono
(vedi [Configurazione](#configurazione) e [Notifiche](#notifiche)).

## Struttura del progetto

```
NDM_Linux-Backup/
├── ndm_linux-backup.sh            lo script
├── ndm_linux-backup.conf.example  modello del file di impostazioni (versionato)
├── ndm_linux-backup.conf          le tue impostazioni (personale, ignorato da Git)
├── my.cnf.example                 modello delle credenziali MySQL/MariaDB
├── pgpass.example                 modello delle credenziali PostgreSQL
├── backup/                        destinazione di default degli archivi (contenuto ignorato da Git)
│   └── .gitkeep                   mantiene la cartella vuota nel repository
├── .github/workflows/ci.yml       controlli automatici (ShellCheck, checkbashisms, versione, test di base)
├── .github/dependabot.yml         aggiornamenti mensili delle GitHub Actions usate dalla CI
├── .gitattributes                 mantiene i fine riga Linux
├── .gitignore                     tiene fuori da Git impostazioni, credenziali e archivi
├── LICENSE                        GNU AGPL v3
├── CHANGELOG.md                   modifiche di ogni versione (in inglese)
├── CITATION.cff                   come citare questo software (usato da GitHub)
├── SECURITY.md                    come segnalare una vulnerabilità
├── README.md                      documentazione in inglese
└── README.it.md                   documentazione in italiano
```

## Versioni

Il progetto segue il [Semantic Versioning](https://semver.org/lang/it/). Versione e data
di rilascio sono nel blocco **APP INFO** in cima a `ndm_linux-backup.sh`, con nome,
descrizione e autore; `--version` li mostra. Ogni versione ha un tag Git `vX.Y.Z` e le
modifiche di ciascuna sono elencate in [CHANGELOG.md](CHANGELOG.md) (in inglese). Le
versioni fino alla 2.0.10 sono state pubblicate come *NDM Backup* su
[GitLab](https://gitlab.com/nidamanx/ndm-backup).

## Licenza e disclaimer

Copyright (C) 2020-2026 Nicola Davide Mannarelli
([@nidamanx](https://github.com/nidamanx))

Questo programma è software libero: puoi ridistribuirlo e/o modificarlo secondo i
termini della **GNU Affero General Public License** pubblicata dalla Free Software
Foundation, nella versione 3 della licenza o (a tua scelta) in qualsiasi versione
successiva (`SPDX-License-Identifier: AGPL-3.0-or-later`). Vedi il file
[LICENSE](LICENSE): il testo della licenza che ha valore legale è quello inglese.

**Citazione.** Se usi questo strumento, o parti del suo codice, nel tuo lavoro o in un
altro progetto, ti chiedo di citare *NDM Linux Backup* di Nicola Davide Mannarelli con
un link a questo repository. Il pulsante **Cite this repository** di GitHub, generato da
[CITATION.cff](CITATION.cff), fornisce una citazione pronta. La licenza richiede già che
le copie ridistribuite o modificate mantengano l'avviso di copyright.

**Disclaimer.** Questo software è fornito "così com'è", senza garanzie di alcun tipo,
esplicite o implicite. In nessun caso l'autore potrà essere ritenuto responsabile di
reclami, danni o altre responsabilità, compresi perdita di dati, backup incompleti o non
ripristinabili e sistemi che non si avviano più dopo un ripristino, derivanti dall'uso o
dall'uso improprio di questo software. Sei l'unico responsabile di come lo usi, della
conservazione e protezione degli archivi che crea e della verifica che si possano
ripristinare. Questa è una traduzione di cortesia: fa fede il testo inglese.
