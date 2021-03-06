import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'dart:async';
import '../model/event.dart';
import '../model/notification_utilities.dart';

class EventFormPage extends StatefulWidget {
  EventFormPage({Key key, this.title, this.event}) : super(key: key);

  final Event event;
  final String title;

  @override
  _EventFormPageState createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _eventNotifications = EventNotifications();

  String _name = '';
  String _description = '';
  String _location = '';
  GeoPoint _geoPoint;
  TextEditingController _locationController;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  bool _startSet = false;
  bool _endSet = false;

  bool locationException = true;

  double _zoom = 10.0;
  Marker marker;
  LatLng _centre = LatLng(43.945947115276184, -78.89606283789982);
  var geocoder = GeocodingPlatform.instance;
  MapController mapController = new MapController();

  Event selectedEvent;

  @override
  void initState() {
    super.initState();

    selectedEvent = widget.event != null ? widget.event : null;
    tz.initializeTimeZones();
    _eventNotifications.init();

    if (selectedEvent != null) {
      _locationController =
          new TextEditingController(text: selectedEvent.location);
    } else {
      _locationController = new TextEditingController();
    }

    getPosition(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomPadding: false,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
        // Some UI design for the form
        height: double.infinity,
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(1.0)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey,
            )
          ],
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.0),
              child: Column(
                children: [
                  _buildTextFormField("Event Name"),
                  _buildTextFormField("Description"),
                  _buildDate("Start Date"),
                  _buildTime("Start Time"),
                  _buildDate("End Date"),
                  _buildTime("End Time"),
                  _buildLocationFormField(),
                  _buildLocationFormButton(),
                  Row(children: [_buildMapButtons(), _buildLocation()]),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          /* Making sure end date time is not less than start date time. Initially 
             same time is okay for easy testing purposes. */
          if (_endDate.compareTo(_startDate) < 0) {
            _showCustomDialog(
                FlutterI18n.translate(
                    context, "eventForm.errorLabels.invalidDateTitle"),
                FlutterI18n.translate(
                    context, "eventForm.errorLabels.invalidDateContent"),
                FlutterI18n.translate(
                    context, "eventForm.errorLabels.errorButton"));
          }
          // Handling rest of validation here, also sending the event back to the function that invoked this
          else if (_formKey.currentState.validate()) {
            Event event = Event(
              name: _name != "" ? _name : selectedEvent.name,
              description:
                  _description != "" ? _description : selectedEvent.description,
              startDateTime: _startSet == false && selectedEvent != null
                  ? selectedEvent.startDateTime
                  : _startDate,
              endDateTime: _endSet == false && selectedEvent != null
                  ? selectedEvent.endDateTime
                  : _endDate,
              location: _location != "" ? _location : '',
              geoPoint: _geoPoint != null ? _geoPoint : GeoPoint(0, 0),
            );
            // Calculating the difference in milliseconds between the event start date and the time it is not
            var secondsDiff = (event.startDateTime.millisecondsSinceEpoch -
                    tz.TZDateTime.now(tz.local).millisecondsSinceEpoch) ~/
                1000;

            // If the start date is greater than one day, send a notification later,
            if (secondsDiff > 0) {
              if (secondsDiff >= 86400) {
                var later = tz.TZDateTime.now(tz.local)
                    .add(Duration(seconds: secondsDiff - 86400));
                _eventNotifications.sendNotificationLater(
                    event.name,
                    event.description,
                    later,
                    event.reference != null ? event.reference.id : null);
              } else {
                // Otherwise send the notification now
                _eventNotifications.sendNotificationNow(
                    event.name,
                    event.description,
                    event.reference != null ? event.reference.id : null);
              }
            }

            // Go back to event list
            Navigator.pop(context, event);
          }
        },
        tooltip: 'Save',
        child: Icon(Icons.save),
      ),
    );
  }

  /*  This function returns a TextFormField based on the argument provided. At 
      the moment this function can cover the event name, description, and 
      imageURL fields (although the imageURL component of the event class has
      not been fully implemented yet). The label, initial value, and the value
      changed are all based on the argument.  */
  Widget _buildTextFormField(String type) {
    String typeVal = "";

    if (type == "Event Name" && selectedEvent != null) {
      typeVal = selectedEvent.name;
    } else if (type == "Description" && selectedEvent != null) {
      typeVal = selectedEvent.description;
    }

    return TextFormField(
      decoration: InputDecoration(
        labelText: type == "Event Name"
            ? FlutterI18n.translate(context, "eventForm.formLabels.name")
            : FlutterI18n.translate(
                context, "eventForm.formLabels.description"),
      ),
      autovalidateMode: AutovalidateMode.always,
      initialValue: selectedEvent != null ? typeVal : '',
      maxLines: type == "Description" ? 3 : 1,
      // Validation to check if empty or not 9 numbers
      validator: (String value) {
        if (value.isEmpty) {
          // return 'Error: Please enter ' + type + '!';
          return type == "Event Name"
              ? FlutterI18n.translate(
                  context, "eventForm.errorLabels.emptyName")
              : FlutterI18n.translate(
                  context, "eventForm.errorLabels.emptyDescription");
          ;
        } else if (type == "Event Name" && value.length > 12) {
          return FlutterI18n.translate(
              context, "eventForm.errorLabels.nameLength");
        }

        return null;
      },
      onChanged: (String newValue) {
        if (type == "Event Name") {
          _name = newValue;
        } else if (type == "Description") {
          _description = newValue;
        }
      },
    );
  }

  /*  This function returns a container consisting of the date related 
      components. The function is designed to handle both the start and
      end dates based on the argument entered.  */
  Widget _buildDate(String type) {
    DateTime _date = DateTime.now();

    // If this function is supposed to build the start date...
    if (type == "Start Date") {
      /* If this form is an edit request (there's a selected event), and a 
         value for the start date has not been picked yet... */
      if (selectedEvent != null && _startSet == false) {
        _date = selectedEvent.startDateTime;
        _startDate = _date;
      } else {
        _date = _startDate;
      }
    }
    /* Otherwise if this function is supposed to build end date, similar 
       logic to above... */
    else if (type == "End Date") {
      if (selectedEvent != null && _endSet == false) {
        _date = selectedEvent.endDateTime;
        _endDate = _date;
      } else {
        _date = _endDate;
      }
    }

    return Container(
      child: Row(
        children: [
          Text(
            type == "Start Date"
                ? FlutterI18n.translate(
                        context, "eventForm.formLabels.startDate") +
                    ": "
                : FlutterI18n.translate(
                        context, "eventForm.formLabels.endDate") +
                    ": ",
            style: TextStyle(color: Colors.grey[700], fontSize: 16.0),
          ),
          Text(_date.day.toString() +
              "/" +
              _date.month.toString() +
              "/" +
              _date.year.toString()),
          FlatButton(
            child: Text(FlutterI18n.translate(
                context, "eventForm.formLabels.selectButton")),
            onPressed: () {
              showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2150))
                  .then((value) {
                setState(() {
                  _date = DateTime(
                    value != null ? value.year : _date.year,
                    value != null ? value.month : _date.month,
                    value != null ? value.day : _date.day,
                    _date.hour,
                    _date.minute,
                    0,
                  );
                  // Setting values based on whether this is a start or end date picker
                  if (type == "Start Date") {
                    _startDate = _date;
                    _startSet = true;
                  } else if (type == "End Date") {
                    _endDate = _date;
                    _endSet = true;
                  }
                  print(type + ": " + _date.toString());
                });
              });
            },
          ),
        ],
      ),
    );
  }

  /* This function is similar to the previous function but is for time related
     components instead. It handles both start and end times based on argument. */
  Widget _buildTime(String type) {
    DateTime _date = DateTime.now();
    TimeOfDay _time = TimeOfDay.now();

    if (type == "Start Time") {
      if (selectedEvent != null && _startSet == false) {
        _date = selectedEvent.startDateTime;
        _startDate = _date;
      } else {
        _date = _startDate;
      }
    } else if (type == "End Time") {
      if (selectedEvent != null && _endSet == false) {
        _date = selectedEvent.endDateTime;
        _endDate = _date;
      } else {
        _date = _endDate;
      }
    }

    _time = TimeOfDay(hour: _date.hour, minute: _date.minute);

    return Container(
      child: Row(children: [
        Text(
          type == "Start Time"
              ? FlutterI18n.translate(
                      context, "eventForm.formLabels.startTime") +
                  ": "
              : FlutterI18n.translate(context, "eventForm.formLabels.endTime") +
                  ": ",
          style: TextStyle(color: Colors.grey[700], fontSize: 16.0),
        ),
        Text(_date.hour.toString() + ":" + minuteToString(_date.minute)),
        FlatButton(
          child: Text(FlutterI18n.translate(
              context, "eventForm.formLabels.selectButton")),
          onPressed: () {
            showTimePicker(
              context: context,
              initialTime: _time,
            ).then((value) {
              setState(() {
                _date = DateTime(
                  _date.year,
                  _date.month,
                  _date.day,
                  value != null ? value.hour : _date.hour,
                  value != null ? value.minute : _date.minute,
                  0,
                );

                if (type == "Start Time") {
                  _startDate = _date;
                  _startSet = true;
                } else if (type == "End Time") {
                  _endDate = _date;
                  _endSet = true;
                }
                print(type + ": " + _date.toString());
              });
            });
          },
        ),
      ]),
    );
  }

  /* Building the form that covers the location field, unlike the others this 
     one has a specific controller to update the value inside based on the 
     current location's postal code (if the user presses the get my location
     button below the zoom buttons). */
  Widget _buildLocationFormField() {
    return TextFormField(
      decoration: InputDecoration(
        labelText:
            FlutterI18n.translate(context, "eventForm.formLabels.location"),
      ),
      autovalidateMode: AutovalidateMode.always,
      validator: (String value) {
        if (value.isEmpty) {
          return FlutterI18n.translate(
              context, "eventForm.errorLabels.emptyLocation");
        } else if (locationException == true) {
          return FlutterI18n.translate(
              context, "eventForm.errorLabels.checkLocation");
        }
        return null;
      },
      onChanged: (String newValue) {
        _location = newValue;
        locationException = true;
      },
      controller: _locationController,
    );
  }

  /* If this button is clicked then the location of the current address inside
     location field is obtained and shown on the map (done in get position). */
  Widget _buildLocationFormButton() {
    return RaisedButton(
      child: Text(FlutterI18n.translate(
          context, "eventForm.formLabels.locationButton")),
      onPressed: () {
        if (_location != '') {
          getPosition(false);
        }
      },
    );
  }

  // Building the map
  Widget _buildLocation() {
    return Container(
      padding: const EdgeInsets.only(top: 10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(1.0)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey,
          )
        ],
      ),
      width: 300.0,
      height: 200.0,
      child: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          minZoom: 5.0,
          zoom: _zoom,
          maxZoom: 20.0,
          center: _centre,
        ),
        layers: [
          TileLayerOptions(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            additionalOptions: {
              'accessToken':
                  'pk.eyJ1IjoibGVvbi1jaG93MSIsImEiOiJja2hyMGRteWcwNjh0MzBteXh1NXNibHY0In0.nFSqVO-aIMytp_hQWKmXXQ',
              'id': 'mapbox.mapbox-streets-v8'
            },
            subdomains: ['a', 'b', 'c'],
          ),
          new MarkerLayerOptions(
            markers: marker != null ? [marker] : [],
          ),
        ],
      ),
    );
  }

  // Building the zoom in, zoom out, and get my location buttons
  Widget _buildMapButtons() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Zoom in button
        IconButton(
          icon: Icon(Icons.zoom_in),
          onPressed: () {
            if (_zoom < 20.0) {
              setState(() {
                _zoom += 1.0;
                mapController.move(_centre, _zoom);
              });
            }
          },
        ),
        // Zoom out button
        IconButton(
            icon: Icon(Icons.zoom_out),
            onPressed: () {
              if (_zoom > 5.0) {
                setState(() {
                  _zoom -= 1.0;
                  mapController.move(_centre, _zoom);
                });
              }
            }),
        // Get my location button (map related actions performed in get position)
        IconButton(
          icon: Icon(Icons.my_location),
          onPressed: () {
            getPosition(true);
          },
        ),
      ],
    );
  }

  // Function to convert minute to string format, will be moved to another file later
  String minuteToString(int minute) {
    if (minute < 10) {
      return "0" + minute.toString();
    } else {
      return minute.toString();
    }
  }

  /* This function gets the current position of the user based on the passed argument
     and whether the user has entered/modified a value in the form field or whether
     there is already a location due to this being an edit form. */
  Future<void> getPosition(bool current) async {
    var location;
    List<Placemark> places;
    try {
      // If the current argument is true then get the user's current position
      if (current == true) {
        location = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);

        // Updating _centre based on the user's current position latitude and longitude
        _centre = LatLng(location.latitude, location.longitude);

        places = await geocoder.placemarkFromCoordinates(
            location.latitude, location.longitude);

        /* Updating _location field which holds the address of the location and 
           the _geoPoint field which will hold the latitude and longitude of the
           position in GeoPoint form same as FireStore. */
        _location = places[0].postalCode.toString();
        _geoPoint = GeoPoint(_centre.latitude, _centre.longitude);

        setState(() {
          // Getting new marker and updating the map
          updateMarker(location);
          mapController.move(_centre, _zoom);

          // Updating location form field with the current position's postal code
          _locationController.value = TextEditingValue(
            text: _location,
            selection: TextSelection.fromPosition(
              TextPosition(offset: _location.length),
            ),
          );
        });
        locationException = false;
      }
      /* If the user has entered a value in the location form field use that as
         an address and get the location (lat and lang) then update global variables
         and the map. */
      else if (_location != '') {
        List<Location> places = await geocoder.locationFromAddress(_location);
        location = places[0];
        _centre = LatLng(location.latitude, location.longitude);
        _geoPoint = GeoPoint(_centre.latitude, _centre.longitude);
        setState(() {
          updateMarker(location);
          mapController.move(_centre, _zoom);
        });
        locationException = false;
      }
      /* If the user has not modified the location field but this is an edit
         form so there is a selected event, then get that event location's 
         position and do the same as above. */
      else if (selectedEvent != null && selectedEvent.location != null) {
        List<Location> places =
            await geocoder.locationFromAddress(selectedEvent.location);
        location = places[0];
        _location = selectedEvent.location;
        _centre = LatLng(location.latitude, location.longitude);
        _geoPoint = GeoPoint(_centre.latitude, _centre.longitude);
        setState(() {
          updateMarker(location);
          mapController.move(_centre, _zoom);
        });
        locationException = false;
      }
    }
    // If there's an exception then we send out an alert, the exception is printed
    on Exception catch (exception) {
      locationException = true;
      _showCustomDialog(
          FlutterI18n.translate(context, "eventForm.errorLabels.errorTitle"),
          exception.toString(),
          FlutterI18n.translate(context, "eventForm.errorLabels.errorButton"));
    }
  }

  // This function calls showDialog inside, created to reduce code
  void _showCustomDialog(String title, String content, String button) {
    showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: <Widget>[
              FlatButton(
                child: Text(button),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
  }

  // Function to add a marker on the map box
  void updateMarker(var position) {
    var newMarker = new Marker(
      width: 70.0,
      height: 70.0,
      point: new LatLng(position.latitude, position.longitude),
      builder: (context) => Container(
          child: IconButton(
        color: Colors.red,
        icon: Icon(Icons.location_on),
        onPressed: () {
          print('Clicked icon!');
        },
      )),
    );
    marker = newMarker;
  }
}
