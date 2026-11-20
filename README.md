# Centro Multimedia (iOS)

Una sola app para iPhone y iPad que reúne los 7 prompts en un centro de entretenimiento gratuito, legal y en castellano.

| Prompt original | Dónde está en la app |
|---|---|
| 1. Centro multimedia | Pestaña **Inicio**: continuar viendo, accesos rápidos, cine gratis en castellano, estado de la biblioteca |
| 2. Biblioteca de películas y series con Jellyfin | Pestaña **Servidor**: conecta tu Jellyfin, explora bibliotecas, temporadas, búsqueda, continuar viendo. Jellyfin convierte MKV/AVI al vuelo |
| 3. Plataforma de música gratuita | Pestaña **Música**: canciones, artistas, álbumes, listas, favoritos, aleatorio, historial, pódcast y fuentes de música libre (Jamendo, FMA, Musopen, RNE…) |
| 4. Plataformas gratuitas para ver películas | Pestaña **Descubrir**: RTVE Play, eFilm, Pluto TV, Rakuten TV (gratis), Plex, Atresplayer, Mediaset Infinity, Tivify, PLATFO… con registro, limitaciones y enlace |
| 5. Reproductor multimedia universal | Reproductor de vídeo a pantalla completa con subtítulos (.srt/.vtt), imagen en imagen, listas y **continuar donde lo dejaste**. Audio en segundo plano y en la pantalla de bloqueo |
| 6. Documentales y contenido educativo | **Descubrir**: documentales, cursos y conferencias filtrables por categoría, idioma, duración y temática, con favoritos y enlaces propios |
| 7. Organización automática de la biblioteca | **Biblioteca › ⋯**: clasifica, renombra, detecta duplicados, descarga carátulas y sinopsis en castellano. **Nunca borra nada** y todo se puede deshacer |

Prioriza el **castellano**: elige la pista de audio en español, busca subtítulos `.es.srt`, descarga títulos y sinopsis de la tienda española y el catálogo puede filtrar "Solo castellano".

---

## 1. Subirla a GitHub (gratis, sin Mac)

1. Crea una cuenta en [github.com](https://github.com) y un repositorio nuevo (por ejemplo `centro-multimedia`). Puede ser privado.
2. Descomprime el zip y sube **todo el contenido** (incluida la carpeta oculta `.github`).
   - Desde el ordenador: botón **Add file › Upload files** y arrastra las carpetas.
   - O con Git: `git init && git add . && git commit -m "Primera versión" && git branch -M main && git remote add origin https://github.com/TU_USUARIO/centro-multimedia.git && git push -u origin main`
3. Ve a la pestaña **Actions**. El flujo **Compilar app iOS** se ejecuta solo en un Mac de GitHub (gratis para repositorios públicos; los privados tienen minutos gratuitos limitados al mes).
4. Cuando termine en verde, abre la ejecución y descarga **CentroMultimedia-ipa** (`CentroMultimedia-sin-firmar.ipa`).

Si sale en rojo, el paso "Mostrar errores" indica la línea exacta: pégamela y lo corrijo.

## 2. Instalarla en tu iPhone

Apple exige firmar las apps. Opciones, de más fácil a más completa:

- **Sideloadly o AltStore (gratis, con tu Apple ID)**: instala la `.ipa` desde un PC con Windows o un Mac. La firma gratuita caduca a los 7 días y hay que renovarla (AltStore lo hace solo).
- **Xcode en un Mac (gratis)**: `brew install xcodegen && xcodegen generate`, abre `CentroMultimedia.xcodeproj`, elige tu Apple ID en *Signing & Capabilities* y pulsa ▶︎ con el iPhone conectado. También caduca a los 7 días.
- **Apple Developer Program (99 €/año)**: firma de un año e instalación por TestFlight.

El identificador de la app es `com.avoperformance.centromultimedia` (en `project.yml`).

## 2a. TestFlight con Codemagic (recomendado: igual que AVO Performance)

`codemagic.yaml` usa la integración de App Store Connect **Codemagic** y el certificado de distribución que ya tiene el equipo AVO.

1. developer.apple.com › Identifiers › + › App ID: `com.avoperformance.centromultimedia`.
2. App Store Connect › Apps › + › Nueva app con ese Bundle ID (SKU `centromultimedia`).
3. Codemagic › Add application › GitHub › `centro-multimedia` › configuración «codemagic.yaml».
4. Start new build › rama `main` › workflow «Centro Multimedia → TestFlight».

## 2b. Alternativa: TestFlight solo con GitHub Actions

Requisito: estar en el **Apple Developer Program** (99 €/año). El flujo `Subir a TestFlight` compila, firma con la firma en la nube de Apple y sube la app.

1. **Registra el identificador** en developer.apple.com › Certificates, IDs & Profiles › Identifiers › + › App IDs › App: Bundle ID explícito `com.avoperformance.centromultimedia`, sin capacidades extra.
2. **Crea la app** en appstoreconnect.apple.com › Apps › + › Nueva app: plataforma iOS, nombre «Centro Multimedia» (si está cogido, añade algo), idioma Español (España), elige ese Bundle ID y como SKU `centromultimedia`.
3. **Crea una clave API** en App Store Connect › Usuarios y acceso › Integraciones › Claves de API del equipo › +, con acceso **Admin**. Descarga el `.p8` (solo se puede una vez) y apunta el **Key ID** y el **Issuer ID**.
4. **Busca tu Team ID** en developer.apple.com › Account › Membership details.
5. **Añade 4 secretos** en GitHub › repositorio › Settings › Secrets and variables › Actions › New repository secret:
   - `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`
   - `ASC_KEY_P8`: abre el `.p8` con un editor de texto y pega todo, incluidas las líneas BEGIN/END.
6. **Lánzalo**: Actions › Subir a TestFlight › Run workflow.
7. A los 10–30 minutos la versión aparece en App Store Connect › TestFlight. Añádete en **Pruebas internas** e instálala con la app TestFlight del iPhone o iPad.

Cada vez que lo lances, el número de compilación sube solo.

## 3. Usarla

**Añadir tus archivos**: Biblioteca › Importar, o copia archivos a *Archivos › En mi iPhone › Centro Multimedia › Entrada* (o desde el Finder/iTunes con el cable). Al abrir la app se ordenan solos:

```
Biblioteca/
├── Peliculas/El laberinto del fauno (2006)/El laberinto del fauno (2006).mp4
├── Series/La casa de papel/Temporada 01/La casa de papel - S01E01.mp4
├── Musica/Artista/Álbum/Artista - Canción.mp3
├── Videos/
└── Duplicados/   ← aquí se apartan las copias, nunca se borran
```

Los nombres siguen el formato de Jellyfin, así que puedes copiar la misma carpeta a tu servidor.

**Formatos**: el reproductor de iOS abre MP4, M4V, MOV, MP3, M4A, AAC, FLAC y WAV. Para **MKV o AVI**, usa tu servidor Jellyfin (los convierte al vuelo) o ábrelos con VLC desde *Compartir*.

**Jellyfin** (gratis y de código abierto): instálalo en tu portátil desde [jellyfin.org](https://jellyfin.org/downloads/server), añade tus carpetas y pon "Español (España)" como idioma de metadatos. En la app, pestaña Servidor, escribe la dirección que muestra (p. ej. `http://192.168.1.20:8096`).

## Tecnología (todo gratuito)

- SwiftUI + AVKit (iOS 16 o posterior), sin dependencias externas.
- Carátulas y sinopsis: API pública de búsqueda de Apple (tienda de España, sin clave).
- Pódcast: directorio público de pódcast + RSS.
- Compilación: XcodeGen + GitHub Actions.

## Aviso legal

La app solo reproduce archivos tuyos o que tengas derecho a reproducir, y enlaza servicios oficiales gratuitos. No incluye ni enlaza fuentes piratas.
