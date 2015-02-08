require 'twitter'
require 'rmagick'
require 'tumblr_client'
include Magick

TW_SQUARE_SIZE = 50 #The size of the images posted on twitter
TM_SQUARE_SIZE = 108 #The size of images post to tumblr
FRAMES = 50 #how many frames in each gif
FRAME_LENGTH = 15 #how long is each frame shown?
FIRST = 0x00000000 #I never actually use this, instead relying on posting the starting values by hand

# select a 25-bit number using a 25-bit LFSR (tap layout due to:
# http://www.xilinx.com/support/documentation/application_notes/xapp052.pdf)
def next_number(last)
	#checks on the value at the 25th point
	tap25 = (last & 0x1000000) != 0 # 1_0000_0000_0000_0000_0000_0000
	#checks on the value at the 22nd point
	tap22 = (last & 0x200000) != 0 # 0_0010_0000_0000_0000_0000_0000
	xnor = !(tap25 ^ tap22)
	
	if xnor
		#"<<" pushes all the digits up
		#the "& 0x1FFFFFF" cuts off any ones that are too large
		#then adds a one to the end - that OR will always return true, because they're shifted everything up
		return ((last << 1) & 0x1FFFFFF) | 0x00000001
	else
		return ((last << 1) & 0x1FFFFFF)
	end
end

#in order to make the twitter postings less predictable, I scrabble the position of all the squares
#using this grid here
$scramble = [[17, 0, 4, 9, 16],
			[10, 1, 15, 22, 21],
			[19, 14, 18, 11, 12],
			[3, 20, 8, 6, 23],
			[2, 7, 5, 24, 13]]

#Draws a single five by five grid, to be posted on twitter
def draw_grid(value)
	#makes an empty image
	grid = Image.new(TW_SQUARE_SIZE*5, TW_SQUARE_SIZE*5) {self.background_color = "white"}
	#this draws things
	squares = Magick::Draw.new
	#sets the color based on the current value
	r, g, b = get_colors(value)
	squares.fill("rgb(#{r}, #{g}, #{b})")

	#iterates through the value
	for i in 0...5
		for j in 0...5
			#checking if each digit is a one or zero
			if value & 2 ** (j + i*5) != 0
				#if it's a zero, it draws a square after passing it through the scrambler
				x = $scramble[i][j] % 5
				y = ($scramble[i][j] - x) / 5
				squares.rectangle(TW_SQUARE_SIZE*x, TW_SQUARE_SIZE*y, TW_SQUARE_SIZE*(x+1), TW_SQUARE_SIZE*(y+1))
			end
		end
	end
	#puts all the squares in the empty image
	squares.draw(grid)
	#sets the file name
	file_name = "grid#{value}.png"
	#draws it and saves it
	grid.write(file_name)
	#return a file path
	return file_name
end

#draws a gif, starting at a given value and continues for a given number of frames
def draw_gif(frames, value)
	#An image list to put all the frames in
	gif = ImageList.new()

	#generates the final value of the gif
	last_value = value
	frames.times do
		last_value = next_number(last_value)
	end

	#gets the color for the first frame
	r1, g1, b1 = get_colors(value)
	#gets the color for the final frame
	r2, g2, b2 = get_colors(last_value)

	#Repeats this process for every frame
	for k in 0...frames
		#gets the next image
		value = next_number(value)
		#makes a new image to put it in
		grid = Image.new(TM_SQUARE_SIZE*5, TM_SQUARE_SIZE*5) {self.background_color = "white"}
		#makes a new draw to hold everything we'll be drawing
		squares = Magick::Draw.new
		#sets the color so that over the course of the gif it transitions from the starting coloring to the ending one
		r = tween(r1, r2, k.to_f/frames)
		g = tween(g1, g2, k.to_f/frames)
		b = tween(b1, b2, k.to_f/frames)
		squares.fill("rgb(#{r},#{g},#{b})")

		#checks each digit for being a one or zero, just like above
		for i in 0...5
			for j in 0...5
				if value & 2 ** (j + i*5) != 0
					#This image doesn't get scrambled because it looks better this way
					squares.rectangle(TM_SQUARE_SIZE*i, TM_SQUARE_SIZE*j, TM_SQUARE_SIZE*(i+1), TM_SQUARE_SIZE*(j+1))
				end
			end
		end
		#puts all the drawings on the grid
		squares.draw(grid)
		#saves it in the imageList
		gif << grid
	end
	#sets the gif delay
	gif.delay = FRAME_LENGTH
	#saves the gif
	gif.write("gif#{value}.gif")
	#and we return the last value of this gif
	return value
end

#give it a start value and an end value and it'll return a point that's percentage between them
def tween(start, finish, percentage)
	difference = finish - start;
	change = difference * percentage
	tween = start + change
	return tween
end

#generated the color based on the current value
def get_colors(count)
	#I throw away the 25th bit, as it is unneeded
	color = count & 0xffffff
	r = color >> 16 & 0xFF
	g = color >> 8 & 0xFF
	b = color & 0xFF
	return r, g, b
end

#The client which interacts with twitter for everyone
#The $ means that it's a global variable
#Put your oauth keys in here
$client_twitter = Twitter::REST::Client.new do |config|
	config.consumer_key = ""
	config.consumer_secret = ""
	config.access_token = ""
	config.access_token_secret = ""
end

#Posts the next image to twitter
def tweet
	#gets what the last value was from the timeline
	last = $client_twitter.user_timeline()[0].text.match('([0-9])+').string.to_i
	#calculates the new value
	next_square = next_number(last)
	#these four numbers produce swastikas, so let's just not post those. I'm comfortable getting done 8 hours early for that
	if next_square == 28928495 || next_square == 32632615 || next_square == 921816 || next_square == 4625936
		next_square = next_number(next_square)
	end
	#draws the square and saves the file name
	file_name = draw_grid(next_square)
	#gets the text of the tweet
	new_tweet = generate_tweet(next_square)
	#opens the file and posts
	File.open(file_name) do |f|
		$client_twitter.update_with_media(new_tweet, f)
	end
	#deletes the file so it doesn't clutter up the place
	File.delete(file_name)
	#And we're done!
	puts "Posted to twitter"
end

#Generates a tweet. Mostly it's just the number but occasionally it posts commentary.
def generate_tweet(value)
	r = Random.new(value)

	tweet = "#{value}."

	if r.rand(36) <= 1
		case r.rand(4).to_i
		when 0
			tweet << aesthetic_statement(r)
		when 1
			tweet << " Only #{33554432 - $client_twitter.user.statuses_count} pictures "
			case r.rand(2).to_i
			when 0
				tweet << " left."
			else
				tweet << " to go."
			end
		when 2
			tweet << question_statement(r)
		else
			tweet << random_statement(r)
		end
	end

	return tweet;
end

#Generates the tags posted to tumblr. Sometimes add commentary.
def generate_tags(value)
	r = Random.new(value)

	tags = "#{value}, gif, bot, five by five,"
	if r.rand(36) <= 1
		case r.rand(4).to_i
		when 0
			tags << aesthetic_statement(r)
		when 1
			last_post = $client_tumblr.posts 'fivebyfivebot.tumblr.com', :type => 'photo', :limit => 1
			total_posts = last_post["blog"]["posts"]
			tags << " #{(33554432/FRAMES).to_i - total_posts} gifs "
			case r.rand(2).to_i
			when 0
				tags << " left."
			else
				tags << " to go."
			end
		when 2
			tags << question_statement(r)
		else
			tags << random_statement(r)
		end
	end

	return tags
end

#makes an aesthetic statement about the picture
def aesthetic_statement(r)
	statement = " I think this one is"
	case r.rand(8).to_i
	when 0
		statement << " exciting."
	when 1
		statement << " beautiful."
	when 2
		statement << " ugly."
	when 3
		statement << " peaceful."
	when 4
		statement << " strange."
	when 5
		statement << " unusual."
	when 6
		statement << " boring."
	else
		statement << " nice."
	end

	return statement
end

#asks a question about the picture
def question_statement(r)
	statement = " What do you think this one"
	case r.rand(4).to_i
	when 0
		statement << " is?"
	when 1
		statement << " means?"
	when 2
		statement << " wants?"
	else
		statement << " is for?"
	end
	return statement
end

#Puts something irrelevant in the comments
def random_statement(r)
	case r.rand(6).to_i
	when 0
		return " :D"
	when 1
		return " Yawn. I'm tired..."
	when 2
		#Dice because it was randomly generated
		return " 🎲🎲🎲"
	when 3
		return " D:"
	when 4
		return " Hm."
	else
		return " ~_~"
	end
end

#the client for accessing tumblr
#Put your other oauth keys in here
$client_tumblr = Tumblr::Client.new({
  :consumer_key => '',
  :consumer_secret => '',
  :oauth_token => '',
  :oauth_token_secret => ''
})

#posts to tumblr
def tumblr
	#Looks at the last post and extracts the last value
	last_post = $client_tumblr.posts 'fivebyfivebot.tumblr.com', :type => 'photo', :limit => 1
	last_value = last_post["posts"][0]["tags"][0]

	#draws the gif based on that
	value = draw_gif(FRAMES, last_value.to_i)

	#posts it to tumblr
	$client_tumblr.photo 'fivebyfivebot.tumblr.com', :tags => generate_tags(value), :data => "gif#{value}.gif"
	#deletes the old picture so it's not cluttering up the place
	File.delete("gif#{value}.gif")
	puts "Posted to tumblr"
end

#Calls both the tumlbr posting and the twittering posting methods
def post_squares
	tumblr()
	tweet()
end

#post them squares
post_squares()
