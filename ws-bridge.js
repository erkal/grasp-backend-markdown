import * as wsm from "./lib/elm-websocket-manager/js/websocket-manager.js";

window.initWebSocketBridge = function (app) {
  wsm.init({ wsOut: app.ports.wsOut, wsIn: app.ports.wsIn });
};
