#include "ota_portal.h"
#include "target_config.h"
#include <WiFi.h>
#include <WebServer.h>
#include <Update.h>
namespace mm::ota {
static bool running=false; static String apSsid;
static const char* AP_PASSWORD="mesh-fpv-ota"; static const char* WEB_USER="mesh"; static const char* WEB_PASSWORD="mesh-fpv-ota";
static WebServer server(80);
static bool auth(){if(server.authenticate(WEB_USER,WEB_PASSWORD))return true;server.requestAuthentication();return false;}
void begin(const String& nodeId){apSsid=String(mm::board::OTA_PREFIX)+"-"+nodeId.substring(nodeId.length()>4?nodeId.length()-4:0);}
void start(){if(running)return;WiFi.mode(WIFI_AP);WiFi.softAP(apSsid.c_str(),AP_PASSWORD);
 server.on("/",HTTP_GET,[]{if(!auth())return;server.send(200,"text/html","<meta name='viewport' content='width=device-width'><h2>Mesh Radio OTA</h2><form method='POST' action='/update' enctype='multipart/form-data'><input type='file' name='firmware' accept='.bin'><button>Update</button></form>");});
 server.on("/update",HTTP_POST,[]{if(!auth())return;bool ok=!Update.hasError();server.send(ok?200:500,"text/plain",ok?"OK - rebooting":"UPDATE FAILED");delay(250);if(ok)ESP.restart();},[]{if(!server.authenticate(WEB_USER,WEB_PASSWORD))return;HTTPUpload& up=server.upload();if(up.status==UPLOAD_FILE_START){Update.begin(UPDATE_SIZE_UNKNOWN);}else if(up.status==UPLOAD_FILE_WRITE){if(Update.write(up.buf,up.currentSize)!=up.currentSize)Update.abort();}else if(up.status==UPLOAD_FILE_END){Update.end(true);}else if(up.status==UPLOAD_FILE_ABORTED){Update.abort();}});
 server.begin();running=true;}
void stop(){if(!running)return;server.stop();WiFi.softAPdisconnect(true);WiFi.mode(WIFI_OFF);running=false;}
void loop(){if(running)server.handleClient();}
bool active(){return running;}
String ssid(){return apSsid;}
}
