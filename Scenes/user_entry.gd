extends CenterContainer
signal user_set(username: String, password: String)

func button_pressed():
	var username = %Username.text.strip_edges()
	var password = %Password.text.strip_edges()
	
	if username == "" or password == "":
		$ErrorLabel.text = "Username and password cannot be empty."
		return
	
	# Emit signal with user credentials
	user_set.emit(username, password)
