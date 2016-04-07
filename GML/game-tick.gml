// Basic input allow flag
// ****************************************************************************

// Update our 'allow basic input' flag
global.gameAllowBasicInput = true;

// Don't allow input if any players are moving/doing stuff
with (obj_parent_game_entity_character_player) {
    if (!is_undefined(self.animation)) {
        global.gameAllowBasicInput = false;
    }
}

// Don't allow input if something else has input focus
if (instance_exists(obj_parent_game_input)) {
    global.gameAllowBasicInput = false;
}

// Turns
// ****************************************************************************

var finishedProcessing = false;

do {
    // Ensure our turn instance hasn't been deleted somehow
    var turnInstanceExists = false;
    with (global.gameTurnInstance) {
        turnInstanceExists = true;
    }
    if (!turnInstanceExists) {
        global.gameTurnInstance = noone;
    }
    
    // Check if we need to update our turn instance
    if (global.gameTurnInstance == noone || global.gameTurnInstance.turnEnded) {
        // Check if a turn just ended
        if (global.gameTurnInstance != noone) {
            // Trigger the end turn event
            with (global.gameTurnInstance) {
                event_perform(ev_other, ev_game_turn_end);
            }
        }
    
        // Find instance whose turn it is
        global.gameTurnInstance = scr_game_turn_find_current_instance();
        
        // Check if a turn just started
        if (global.gameTurnInstance != noone) {
            // Trigger the start turn event
            with (global.gameTurnInstance) {
                event_perform(ev_other, ev_game_turn_start);
            }
        }
    }
    
    // Check if we have a turn instance to process the turn for
    if (global.gameTurnInstance == noone) {
        // No turn instance - everyone's turn is over?
        
        // Increase counter
        self.allTurnsEndedCounter++;
        
        // Restart everyone's turns
        with (obj_parent_game_entity_character) {
            self.turnEnded = false;
            self.ap = self.maxAP;
            
            // Restore PP
            if (other.allTurnsEndedCounter % self.ppRegenTurns == 0) {
                scr_game_stat_update_pp(1);
            }
        }
        
        // Done processing for now - will continue in the next step
        finishedProcessing = true;
    } else {
        // Have turn instance - process their turn
        with (global.gameTurnInstance) {
            // Check if their turn has already ended
            scr_game_turn_check_ended();
        
            if (!self.turnEnded) {
                // Process
                event_perform(ev_other, ev_game_turn);
                
                // Check if their turn ended after processing
                scr_game_turn_check_ended();
            }
            
            // Check if their turn ended immediately (as if it did we'll continue processing)
            if (!self.turnEnded) {
                // Didn't end immediately - we should stop processing
                finishedProcessing = true;
                
                // In Combat mode the view follows the character whose turn it is (if they're visible!)
                if (global.gameCombatMode && self.turnStarted && self._visible) {
                    global.gameViewTargetX = DX(self.drawX + TS/2, self.drawY + TS/2) - view_wview[0]/2;
                    global.gameViewTargetY = DY(self.drawX + TS/2, self.drawY + TS/2) - view_hview[0]/2;
                }
            }
        }
    }
} until (finishedProcessing);

// Visibility
// ****************************************************************************

// Handle calculating the visibility of entities and tiles for our "fog of war" system

// Check if we should update visibility
if (global.gameShouldUpdateVisibility) {
    // Settings
    //var radius = 15;
    //var visWR = 16;
    //var visHR = 11;
    var visWR = 16;
    var visHR = 13;
    
    // Setup calculation
    var w = room_width/TS;
    var h = room_height/TS;
    var dx;
    var dy;
    var visMap;
    var opaqueMap;
    //var fadeMap;
    
    var done;
    var cx;
    var cy;
    var minAngle;
    var row;
    var obstaclesInLastLine;
    var i;
    var startAngle;
    var endAngle;
    var totalObstacles;
    var obstaclesInLastLine;
    
    // Reset visible map and initialise opaque/fade maps
    for (dx = 0; dx < w; dx++) {
        for (dy = 0; dy < h; dy++) {
            visMap[dx, dy] = false;
            opaqueMap[dx, dy] = undefined;
            //fadeMap[dx, dy] = 1;
        }
    }
    
    // Build array of players
    var players;
    var numPlayers = 0;
    with (obj_parent_game_entity_character_player) {
        players[numPlayers++] = self.id;
    }
    
    // Iterate over players
    var p;
    for (p = 0; p < numPlayers; p++) {
        with (players[p]) {
            // Store our starting position and mark it as visible
            var sx = TXI(self.x);
            var sy = TYI(self.y);
            
            visMap[sx, sy] = true;
            
            // Update our 'not opaque' map
            //for (dx = -radius; dx <= radius; dx++) {
            //    for (dy = -radius; dy <= radius; dy++) {
            for (dx = -visWR; dx <= visWR; dx++) {
                for (dy = -visHR; dy <= visHR; dy++) {
                    if (sx + dx >= 0 && sx + dx < w && sy + dy >=0 && sy + dy < h && is_undefined(opaqueMap[sx + dx, sy + dy])) {
                        opaqueMap[sx + dx, sy + dy] = !position_meeting((sx + dx)*TS, (sy + dy)*TS, obj_parent_game_entity_solid_opaque)
                    }
                }
            }
        
            // Iterate over quadrants
            for (dx = -1; dx <= 1; dx += 2) {
                for (dy = -1; dy <= 1; dy += 2) {
                    // Start vertical processing
                    cx = 0;
                    cy = sy + dy;
                    
                    done = false;
                    row = 1;
                    minAngle = 0;
                    obstaclesInLastLine = 0;
                    totalObstacles = 0;
                    
                    // Confirm our position is valid
                    if (cy < 0 || cy >= h) {
                        done = true;
                    }
                    
                    // Process rows until we're done
                    while (!done) {
                        var slopesPerCell = 1/(row + 1);
                        var halfSlopes = slopesPerCell * 0.5;
                        var cell = floor(minAngle / slopesPerCell);
                        var minX = max(0, sx - row);
                        var maxX = min(w - 1, sx + row);
                        
                        done = true;
                        cx = sx + (cell * dx);
                        
                        // Iterate over cells on this row
                        while ((cx >= minX) && (cx <= maxX)) {
                            // Stop if this cell is outside of our FOV
                            //if (row*row + cell*cell > radius*radius) {
                            if (row > visHR) {
                                done = true;
                                break;
                            }
                        
                            var vis = true;
                            var startSlope = cell * slopesPerCell;
                            var middleSlope = startSlope + halfSlopes;
                            var endSlope = startSlope + slopesPerCell;
                            
                            if (obstaclesInLastLine > 0 && !visMap[cx, cy]) {
                                i = 0;
                                while (vis && i < obstaclesInLastLine) {
                                    if (opaqueMap[cx, cy]) {
                                        if (middleSlope > startAngle[i] && middleSlope < endAngle[i]) {
                                            vis = false;
                                        }
                                    } else if (startSlope >= startAngle[i] && endSlope <= endAngle[i]) {
                                        vis = false;
                                    }
                                    
                                    if (vis && (!visMap[cx, cy - dy] || !opaqueMap[cx, cy - dy]) &&
                                            cx - dx >= 0 && cx - dx < w &&
                                            (!visMap[cx - dx, cy - dy] || !opaqueMap[cx - dx, cy - dy])) {
                                        vis = false;
                                    }
                                    i++;
                                }
                            }
                            
                            if (vis) {
                                visMap[cx, cy] = true;
                                //fadeMap[cx, cy] = min(fadeMap[cx, cy], (row*row + cell*cell)/(radius*radius));
                                done = false;
                                
                                if (!opaqueMap[cx, cy]) {
                                    if (minAngle >= startSlope) {
                                        minAngle = endSlope;
                                    } else {
                                        startAngle[totalObstacles] = startSlope;
                                        endAngle[totalObstacles] = endSlope;
                                        totalObstacles++;
                                    }
                                }
                            }
                            
                            cell += 1;
                            cx += dx;
                        }
                        
                        // Update our row
                        row++;
                        
                        // Store the number of obstacles in the row we processed
                        obstaclesInLastLine = totalObstacles;
                        
                        // Update our position and confirm it's valid
                        cy += dy;
                        if (cy < 0 || cy >= h) {
                            done = true;
                        }
                        
                        // Check if we've finished our angles
                        if (minAngle == 1.0) {
                            done = true;
                        }
                    }
                    
                    // Start horizontal processing
                    cx = sx + dx;
                    cy = 0;
                    
                    done = false;
                    row = 1;
                    minAngle = 0;
                    obstaclesInLastLine = 0;
                    totalObstacles = 0;
                    
                    // Confirm our position is valid
                    if (cx < 0 || cx >= w) {
                        done = true;
                    }
                    
                    // Process rows until we're done
                    while (!done) {
                        var slopesPerCell = 1/(row + 1);
                        var halfSlopes = slopesPerCell * 0.5;
                        var cell = floor(minAngle / slopesPerCell);
                        var minY = max(0, sy - row);
                        var maxY = min(h - 1, sy + row);
                        
                        done = true;
                        cy = sy + (cell * dy);
                        
                        // Iterate over cells on this row
                        while ((cy >= minY) && (cy <= maxY)) {
                            // Stop if this cell is outside of our FOV
                            //if (row*row + cell*cell > radius*radius) {
                            if (row > visWR) {
                                done = true;
                                break;
                            }
                            
                            var vis = true;
                            var startSlope = cell * slopesPerCell;
                            var middleSlope = startSlope + halfSlopes;
                            var endSlope = startSlope + slopesPerCell;
                            
                            if (obstaclesInLastLine > 0 && !visMap[cx, cy]) {
                                i = 0;
                                while (vis && i < obstaclesInLastLine) {
                                    if (opaqueMap[cx, cy]) {
                                        if (middleSlope > startAngle[i] && middleSlope < endAngle[i]) {
                                            vis = false;
                                        }
                                    } else if (startSlope >= startAngle[i] && endSlope <= endAngle[i]) {
                                        vis = false;
                                    }
                                    
                                    if (vis && (!visMap[cx - dx, cy] || !opaqueMap[cx - dx, cy]) &&
                                            cy - dy >= 0 && cy - dy < h &&
                                            (!visMap[cx - dx, cy - dy] || !opaqueMap[cx - dx, cy - dy])) {
                                        vis = false;
                                    }
                                    i++;
                                }
                            }
                            
                            if (vis) {
                                visMap[cx, cy] = true;
                                //fadeMap[cx, cy] = min(fadeMap[cx, cy], (row*row + cell*cell)/(radius*radius));
                                done = false;
                                
                                if (!opaqueMap[cx, cy]) {
                                    if (minAngle >= startSlope) {
                                        minAngle = endSlope;
                                    } else {
                                        startAngle[totalObstacles] = startSlope;
                                        endAngle[totalObstacles] = endSlope;
                                        totalObstacles++;
                                    }
                                }
                            }
                            
                            cell += 1;
                            cy += dy;
                        }
                        
                        // Update our row
                        row++;
                        
                        // Store the number of obstacles in the row we processed
                        obstaclesInLastLine = totalObstacles;
                        
                        // Update our position and confirm it's valid
                        cx += dx;
                        if (cx < 0 || cx >= w) {
                            done = true;
                        }
                        
                        // Check if we've finished our angles
                        if (minAngle == 1.0) {
                            done = true;
                        }
                    }
                }
            }
        }
    }
    
    // Update visible/seen maps using our results
    for (dx = 0; dx < w; dx++) {
        for (dy = 0; dy < h; dy++) {
            global.gameVisibleMap[dx, dy] = visMap[dx, dy];
            global.gameSeenMap[dx, dy] = global.gameSeenMap[dx, dy] || visMap[dx, dy];
        }
    }
    
    // Update entities using our results
    with (obj_parent_game_entity_with_visibility) {
        dx = TXI(self.x);
        dy = TYI(self.y);
        
        self._visible = visMap[dx, dy];
        self.seen = self.seen || self._visible;
    }
    
    // Trigger a minimap update
    with (obj_game_controller_hud) {
        event_perform(ev_other, ev_game_action);
    }
    
    // Done
    global.gameShouldUpdateVisibility = false;
}

// Update visible color/alpha
var w = room_width/TS;
var h = room_height/TS;
var dx;
var dy;

for (dx = 0; dx < w; dx++) {
    for (dy = 0; dy < h; dy++) {
        if (!global.gameVisibleMap[dx, dy]) {
            if (global.gameSeenMap[dx, dy]) {
                global.gameVisibleColorMap[dx, dy] = merge_color(global.gameVisibleColorMap[dx, dy], c_gray, 0.2);
                global.gameVisibleAlphaMap[dx, dy] = min(global.gameVisibleAlphaMap[dx, dy] + 0.05, 1);
            }
        } else {
            global.gameVisibleColorMap[dx, dy] = merge_color(global.gameVisibleColorMap[dx, dy], c_white, 0.2);
            global.gameVisibleAlphaMap[dx, dy] = min(global.gameVisibleAlphaMap[dx, dy] + 0.05, 1);
        }
    }
}