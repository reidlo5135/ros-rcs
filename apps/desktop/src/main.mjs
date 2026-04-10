import { app, BrowserWindow, screen } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function createMainWindow() {
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width: displayWidth, height: displayHeight } = primaryDisplay.size;

  const width = Math.floor(displayWidth * 0.85);
  const height = Math.floor(displayHeight * 0.8);

  const mainWindow = new BrowserWindow({
    width,
    height,
    minWidth: 900,
    minHeight: 700,
    icon: path.resolve(__dirname, "../assets/favicon.ico"),
    autoHideMenuBar: true,
    show: false,
    backgroundColor: "#e8e8e6",
    title: "RCS",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.once("ready-to-show", () => {
    mainWindow.center();
    mainWindow.show();
  });

  const rendererUrl = process.env.RCS_RENDERER_URL;
  if (rendererUrl) {
    void mainWindow.loadURL(rendererUrl);
    return;
  }

  const indexPath = path.resolve(__dirname, "../../web/dist/index.html");
  void mainWindow.loadFile(indexPath);
}

app.whenReady().then(() => {
  createMainWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
