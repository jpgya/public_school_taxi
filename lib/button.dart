
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';



class DropdownButtonMenu extends StatefulWidget {
  const DropdownButtonMenu({
    super.key,
    required this.title,
    required this.list,
    required this.value,
    required this.showError,
    required this.onChanged,
    required this.controller,
  });

  final String title;
  final List<String> list;
  final String? value;
  final bool showError;
  final Function(String?) onChanged;
  final TextEditingController? controller;

  @override
  State<DropdownButtonMenu> createState() => _DropdownButtonMenuState();
}
class _DropdownButtonMenuState extends State<DropdownButtonMenu> {

  @override
  Widget build(BuildContext context) {

    return SizedBox(
      height: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 80,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.showError ? Colors.red : Colors.white,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: DropdownMenu<String>(
                  controller: widget.controller,
                  width: 400,
                  initialSelection: widget.value,
                  requestFocusOnTap: true,
                  enableSearch: true,
                  enableFilter: true,
                  label: Text(widget.title),
                  textStyle: TextStyle(fontSize: 22),
                  onSelected: widget.onChanged,
                  dropdownMenuEntries: widget.list.map((e) {
                    return DropdownMenuEntry(
                      value: e,
                      label: e,
                      style: MenuItemButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          if (widget.showError)
            SizedBox(
              height: 25,
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.only(top: 0, left: 20),
                  child: Text(
                    '${widget.title} が入力されていません。',
                    style: TextStyle(color: Colors.red, fontSize: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NavigateButton extends StatefulWidget{
  const NavigateButton({super.key, required this.title, required this.next ,required this.buttonColor, required this.textColor});
  final String title;
  final Widget next;
  final Color buttonColor;
  final Color textColor;

  @override
  State<NavigateButton> createState() => _NavigateButtonState();
}
class _NavigateButtonState extends State<NavigateButton> {

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
        style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(widget.buttonColor as Color?)),
        onPressed: (){


          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => widget.next),
          );

        },
        child: FittedBox(child: Text( widget.title,style: TextStyle(color: widget.textColor as Color?, fontSize:30 ),))
    );
  }
}