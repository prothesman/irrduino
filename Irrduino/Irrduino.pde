/**
  Irrduino v0.8 by Joe Fernandez

  Issues:
  - need a nanny process to set a max run time for valves (regardless of commands or program)
  - add a "status" option for each zone individually and all zones together
  - add sending event reports to web server for reporting

  Change Log:
  - 2011-11-10 - add global status option
  - 2011-10-27 - added code to turn on and blink an LED on pin 13 while zone running
  - 2011-10-07 - fixed problem with home page not displaying after first request
               - fixed problem mismatch between zone/pin selection
  - 2011-10-05 - Version 0.6 completed
               - 3 file split, commandDispatch[] infrastructure implemented
               - fixed problem with zone command being run repeatedly 
  - 2011-09-28 - Split pde into parts for easier code management
               - Introduced new commandDispatch[] object for storing command parameters
  - 2011-09-25 - Added web UI for more zones and "ALL OFF" function
  - 2011-09-xx - Entended parser to turn off zones individually
  - updated to use timer for executing irrigation zone runs; now runs can be interrupted

  An irrigation control program with a REST-like http 
  remote control protocol.
  
  Based on David A. Mellis's "Web Server" ethernet
  shield example sketch.
   
  REST implementation based on "RESTduino" sketch 
  by Jason J. Gullickson
 */

#include <SPI.h>
#include <Ethernet.h>


byte mac[] = { 0x90, 0xA2, 0xDA, 0x00, 0x50, 0xA0 };    //physical mac address
byte ip[] = { 192, 168, 1, 14 };			// ip in lan
byte gateway[] = { 192, 168, 1, 1 };			// internet access via router
byte subnet[] = { 255, 255, 255, 0 };                   //subnet mask

Server server(80);                                      //server port
Client client = NULL;                                   // client

// zone to pin mapping
int zone1 = 2; //pin 2
int zone2 = 3; //pin 3
int zone3 = 4; //pin 4
int zone4 = 5; //pin 5
int zone5 = 6; //pin 6
int zone6 = 7; //pin 7
int zone7 = 8; //pin 8
int zone8 = 9; //pin 9
int zone9 = 11; //pin 11
int zone10 = 12; //pin 12

// LED indicator pin variables
int ledIndicator = 13;
int ledState = LOW;
unsigned long ledFlashTimer = 0;       // timer for LED in milliseconds
unsigned long ledFlashInterval = 1000; // flash interval in milliseconds

// set the maximum run time for a zone (safeguard)
unsigned long MAX_RUN_TIME_MINUTES = 30;  // Default 30 minutes
unsigned long MAX_RUN_TIME = MAX_RUN_TIME_MINUTES * 60000;

int zones[] = {zone1, zone2, zone3, zone4, zone5, 
                   zone6, zone7, zone8, zone9, zone10};
int zoneCount = 10;

// Uri Object identifier

const int OBJ_CMD_ALL_OFF  = 1;
const int OBJ_CMD_STATUS   = 2;
const int OBJ_CMD_ZONE     = 10;
const int OBJ_CMD_ZONES    = 100;
const int OBJ_CMD_PROGRAM  = 20;
const int OBJ_CMD_PROGRAMS = 200;

const int OFF = 0;
const int ON =  1;

int commandDispatchLength = 5;
int commandDispatch[]     = { 0, // command object type, 0 for none 
                              0, // command object id, 0 for none
                              0, // command code, 0 for none
                              0, // value 1, 0 for none
                              0  // value 2, 0 for none
                              };
const int CMD_OBJ  = 0;
const int OBJ_ID   = 1;
const int CMD_CODE = 2;
const int VALUE_1  = 3;
const int VALUE_2  = 4;
                          
unsigned long commandRunning[] = {0, // zoneID, 0 for none
                                  0  // run end time in miliseconds, 0 for none 
                                  };

                                  
String jsonReply;

void setup(){
  // Turn on serial output for debugging
  Serial.begin(9600);

  // Start Ethernet connection and server
  Ethernet.begin(mac, ip, gateway, subnet);
  server.begin();
  
  //Set relay pins to output
  for (int i = 0; i < zoneCount; i++){
    pinMode(zones[i], OUTPUT);  
  }
  
  // set the LED indicator pin for output
  pinMode(ledIndicator, OUTPUT);
}

//  url buffer size
#define BUFSIZE 255

void loop(){
  char clientLine[BUFSIZE];
  int index = 0;

  // check on timed runs, shutdown expired runs
  checkTimedRun();    

  // listen for incoming clients
  client = server.available();
  if (client) {

    //  reset input buffer
    index = 0;

    while (client.connected()) {
      if (client.available()) {
        char c = client.read();

        //  fill buffer with url
        if(c != '\n' && c != '\r'){
          
          //  if we run out of buffer, overwrite the end
          if(index >= BUFSIZE) {
            break;
            //index = BUFSIZE -1;
          }

          clientLine[index] = c;
          index++;

//          Serial.print("client-c: ");
//          Serial.println(c);
          continue;
        } 
        Serial.print("http request: ");
        Serial.println(clientLine);

        //  convert clientLine into a proper
        //  string for further processing
        String urlString = String(clientLine);

        if (urlString.lastIndexOf("TTP/1.1") < 0 ){
          Serial.println("no HTTP/1.1, ignoring request");
          // not a url request, ignore this
          goto finish_http;
        }

        //  extract the operation (GET or POST)
        String op = urlString.substring(0,urlString.indexOf(' '));

        //  we're only interested in the first part...
        urlString = urlString.substring(
		urlString.indexOf('/'), 
		urlString.indexOf(' ', urlString.indexOf('/')));

        //  put what's left of the URL back in client line
        urlString.toCharArray(clientLine, BUFSIZE);

        //  get the parameters
        char *arg1 = strtok(clientLine,"/");
        Serial.print("arg1: ");
        Serial.println(arg1);
        char *arg2 = strtok(NULL,"/");
        Serial.print("arg2: ");
        Serial.println(arg2);
        char *arg3 = strtok(NULL,"/");
        Serial.print("arg3: ");
        Serial.println(arg3);
        char *arg4 = strtok(NULL,"/");
        Serial.print("arg4: ");
        Serial.println(arg4);

        if (arg1 == NULL){
	  // we got no parameters. show default page
	  httpHomePage();

	} else {
          // start a json reply
          jsonReply = String();
          // identify the command
          findCmdObject(arg1);
          
          switch (commandDispatch[CMD_OBJ]) {
            
            case OBJ_CMD_ALL_OFF:   // all off command
              cmdZonesOff();
              break;

            case OBJ_CMD_STATUS: // Global status ping
              cmdStatusRequest();
              break;
            
            case OBJ_CMD_ZONE:      // zone command
              
              findZoneCommand(arg2);
              
              switch (commandDispatch[CMD_CODE]){
                 case OFF:
                   endTimedRun();
                   break;
                 case ON:
                   findZoneTimeValue(arg3);
                   cmdZoneTimedRun();
                   break;
              }

              break;
            case OBJ_CMD_ZONES:     // all zones
              break;
            case OBJ_CMD_PROGRAM:   // program command
              break;
            case OBJ_CMD_PROGRAMS:  // all programs
              break;
            default:
              httpJsonReply("\"ERROR\":\"Command not recognized.\"");
          }
	}
      }
    }
    
    // finish http response
    finish_http:
    
    // clear Command Dispatch
    Serial.println("clearCommandDispatch()");
    clearCommandDispatch();
    
    // Clear the clientLine char array
    Serial.println("clear client line: clearCharArray()");
    clearCharArray(clientLine, BUFSIZE);
    
    // give the web browser time to receive the data
    delay(20);
    
    // close the connection:
    client.stop();
    
  }
} /// ========= end loop() =========

void findCmdObject(char *cmdObj){

    String commandObject = String(cmdObj);
    commandObject = commandObject.toLowerCase();
     
    // check for "OFF" shortcut
    if (commandObject.compareTo("off") == 0) {
        commandDispatch[CMD_OBJ] = OBJ_CMD_ALL_OFF;
        jsonReply += "\"command\":\"zones off\"";
        return;
    }
    
    // check for global "status" request
    if (commandObject.compareTo("status") == 0) {
        commandDispatch[CMD_OBJ] = OBJ_CMD_STATUS;
        return;
    }
    
    // must check for plural form first
    if (commandObject.compareTo("zones") == 0) {
        commandDispatch[CMD_OBJ] = OBJ_CMD_ZONES;
        jsonReply += "\"zones\":";
        return;
    }

    if (commandObject.startsWith("zone")) {
        commandDispatch[CMD_OBJ] = OBJ_CMD_ZONE; // command object type, 0 for none
        jsonReply += "\"zone";

        // get zone number  
        String zoneNumber = commandObject.substring(
		commandObject.lastIndexOf('e') + 1, 
		commandObject.length() );
        
        commandDispatch[OBJ_ID] = stringToInt(zoneNumber); // command object id, 0 for none
        jsonReply += zoneNumber;
        jsonReply += "\":";
        return;
    }
    
    // must check for plural form first
    if (commandObject.compareTo("programs") == 0) {
        commandDispatch[CMD_OBJ] = OBJ_CMD_PROGRAMS;
        jsonReply += "\"programs\":";
        return;
    }
    if (commandObject.startsWith("program")) {
        commandDispatch[CMD_OBJ] = OBJ_CMD_PROGRAM;
        jsonReply += "\"program";

        // get program number
        String progNumber = commandObject.substring(
		commandObject.lastIndexOf('m') + 1, 
		commandObject.length() );

        commandDispatch[OBJ_ID] = stringToInt(progNumber); // command object id, 0 for none
        jsonReply += progNumber;
        jsonReply += "\":";
        return;
    }
     
}

// interprets the command following the /zoneX/ command prefix
void findZoneCommand(char *zoneCmd){
  
    String zoneCommand = String(zoneCmd);
    zoneCommand = zoneCommand.toLowerCase();
     
    // check for "ON"
    if (zoneCommand.compareTo("on") == 0) {
        commandDispatch[CMD_CODE] = ON;
        jsonReply += "\"on\"";
        return;
    }
  
    // check for "OFF"
    if (zoneCommand.compareTo("off") == 0) {
        commandDispatch[CMD_CODE] = OFF;
        jsonReply += "\"off\"";
        return;
    }
}

void findZoneTimeValue(char *zoneTime){
  int time = atoi(zoneTime);
  commandDispatch[VALUE_1] = time;  
}

// Utility functions

void clearCharArray(char array[], int length){
  for (int i=0; i < length; i++) {
    //if (array[i] == 0) {break; };
    array[i] = 0;
  }
}

void clearCommandDispatch(){
    for (int i = 0; i < commandDispatchLength; i++){
        commandDispatch[i] = 0;
    }
}

// standard function for debug/logging
void writeLog(String logMsg){

  Serial.println(logMsg);

  //TODO: buffer log message for web delivery
  //TODO: write log message to SDCard (if available)

}

int stringToInt(String value){
  // remember to add 1 to the length for the terminating null
  char buffer[value.length() +1]; 
  value.toCharArray(buffer, value.length() +1 );
  return atoi(buffer);
}
