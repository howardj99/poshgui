var header = document.querySelector('header');
var section = document.querySelector('section');

var requestURL = 'https://api.myjson.com/bins/gfzrq'; //JSON hosted at myjson.com for testing
var request = new XMLHttpRequest();

request.open('GET', requestURL);
request.responseType = 'json';
request.send();

request.onload = function() {
    var jsonObject = request.response;
    getUserScript(jsonObject);
}

function getUserScript(jsonObject) {
    var scriptEntry      = jsonObject['ScriptEntry'];
    var utilityFunctions = jsonObject['UtilityFunctions'];
    var jobCleanup       = jsonObject['JobCleanup'];
    var eventHandlers    = jsonObject['EventHandlers'];
    var scriptExecution  = jsonObject['ScriptExecution'];

    var userScript: string = 
        scriptEntry.Header +
        scriptEntry.Body.Declarations +
        scriptEntry.Body.Xaml +
        scriptEntry.Footer +
        utilityFunctions.Header +
        utilityFunctions.Body +
        utilityFunctions.Footer +
        jobCleanup.Header +
        jobCleanup.Body +
        jobCleanup.Footer +
        eventHandlers.Header +
        eventHandlers.Body[0] + //to-do: loop
        eventHandlers.Footer +
        scriptExecution.Header +
        scriptExecution.Body.XamlImport +
        scriptExecution.Body.EventSubscriptions[0] + //to-do: loop
        scriptExecution.Body.WindowLaunch +
        scriptExecution.Footer;

    var textArea: HTMLTextAreaElement = document.createElement('textarea');
    textArea.rows = 100;
    textArea.cols = 160;
    textArea.textContent = userScript;

    section.appendChild(textArea);
}