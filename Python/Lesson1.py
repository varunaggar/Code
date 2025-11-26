# print("Hello")
# print("this is a python program")

# thisisaVariable = "this is a string variable, letts print it"
# print(thisisaVariable)

# thisisaVariable = "Adding another line to the same variable"
# print(thisisaVariable)

# Naming_Variable = "Variables can start with letters or _ only. they cannot start with a number"
# print(Naming_Variable)

# _Variable = "this is another exmaple of variable starting with _"
# print(_Variable)

# # Learning Strings
# # Using String variables
# # title, upper and lower are methods action on the data stored in the variable
# _Var_String = "varun aggarwal"
# print(_Var_String)
# print(_Var_String.title())
# print(_Var_String.upper())
# print(_Var_String.lower())
# print(thisisaVariable.upper())

# # Use f at the start of the line to store value of variable in a string. f means format
# first_name = "ada"
# last_name = "lovelace"
# full_name = f"{first_name} {last_name}"
# print(full_name)

# first_name = "ada"
# last_name = "lovelace"
# full_name = f"\n{first_name} \n{last_name}"
# print(f"Hello, {full_name.title()}!")

# # Remvoing trailing spaces using lstrip and rstrip
# _Space = "There is a space at the end "
# print(_Space.rstrip())
# print(_Space.lstrip())

# # Removing prefix and suffix
# _prefix = "https://www.bbc.com"
# print(_prefix.removeprefix("https://"))
# print(_prefix.removesuffix(".com"))

# # Numbers
# _a = 2
# # _b = 3
# _sum = _a + _b
# print(_sum)
# print(_a + _b)
# print(_a * _b)
# print(_a ** _b)
# print(_a / _b)
# print(_a - _b)
# print(_b/_a)

# _a,_b,_c = 1,2,3
# print(_a+_b+_c)
# print((_a+_b)*_c)
# print(_a+_b-_c)

# # Lists
# bicycles = ['trek', 'cannondale', 'redline', 'specialized']
# print(bicycles)
# print(bicycles[0])
# print(bicycles[-3])
# print(bicycles[0].upper())

# motorcycles = ['honda', 'yamaha', 'suzuki']
# print(motorcycles)

# motorcycles[0] = 'ducati'
# print(motorcycles)

# motorcycles = ['honda', 'yamaha', 'suzuki']
# print(motorcycles)

# motorcycles.append('ducati')
# print(motorcycles)

# motorcycles = []

# motorcycles.append('honda')
# motorcycles.append('yamaha')
# motorcycles.append('suzuki')

# print(motorcycles)

# motorcycles = ['honda', 'yamaha', 'suzuki']

# motorcycles.insert(0, 'ducati')
# print(motorcycles)

# del motorcycles[1]
# print(motorcycles)

# motorcycles = ['honda', 'yamaha', 'suzuki']
# print(motorcycles)

# popped_motorcycle = motorcycles.pop()
# print(motorcycles)
# print(popped_motorcycle)

# motorcycles = ['honda', 'yamaha', 'suzuki']

# last_owned = motorcycles.pop()
# print(f"The last motorcycle I owned was a {last_owned.title()}.")

# motorcycles = ['honda', 'yamaha', 'suzuki']

# first_owned = motorcycles.pop(0)
# print(motorcycles)
# print(f"The first motorcycle I owned was a {first_owned.title()}.")

# motorcycles = ['honda', 'yamaha', 'suzuki', 'ducati']
# print(motorcycles)

# motorcycles.remove('ducati')
# motorcycles.sort()
# print(motorcycles)

# cars = ['bmw', 'audi', 'toyota', 'subaru']

# print("Here is the original list:")
# print(cars)

# print("\nHere is the sorted list:")
# print(sorted(cars))

# print("\nHere is the original list again:")
# print(cars)

# places = ["London","Tokyo","Singapore","Bali"]
# print(f"This is the original list of places \n{places}" )

# print(f"This is the original list of places \n{places[0]}\n{places[1]}\n{places[2]}\n{places[3]}" )

# print(sorted(places))

import random

RED = '\033[91m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
CYAN = '\033[96m'
RESET = '\033[0m'
computer_choice = random.choice(["rock", "paper", "scissors"])
quit = False

while not quit:
    user_choice = input(CYAN + "Do you want - rock, paper or scissors? " + RESET).strip().lower()
    computer_choice = random.choice(["rock", "paper", "scissors"])
    while user_choice not in ["rock", "paper", "scissors"]:
        user_choice = input(RED + "Invalid choice. Please choose rock, paper or scissors: " + RESET).strip().lower()
    
    if computer_choice == user_choice:
        print(YELLOW + "It's a draw!" + RESET)
    elif user_choice == "rock" and computer_choice == "scissors":
        print(GREEN + "You win! Rock crushes scissors." + RESET)
    elif user_choice == "paper" and computer_choice == "rock":
        print(GREEN + "You win! Paper covers rock." + RESET)
    elif user_choice == "scissors" and computer_choice == "paper":
        print(GREEN + "You win! Scissors cut paper." + RESET)
    else:
        print(RED + f"You lose! {computer_choice} beats {user_choice}." + RESET)

    play_again = input(CYAN + "Do you want to play again? (y/nri)").strip().lower()
    if play_again != "y":
        quit = True
