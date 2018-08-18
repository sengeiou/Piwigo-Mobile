//
//  EditImageLabelTableViewCell.m
//  piwigo
//
//  Created by Spencer Baker on 2/16/15.
//  Copyright (c) 2015 bakercrew. All rights reserved.
//

#import "EditImageLabelTableViewCell.h"
#import "Model.h"

@interface EditImageLabelTableViewCell()

@property (weak, nonatomic) IBOutlet UILabel *leftLabel;
@property (weak, nonatomic) IBOutlet UILabel *rightLabel;


@end

@implementation EditImageLabelTableViewCell

- (void)awakeFromNib {

    // Initialization code
    [super awakeFromNib];
	
    self.leftLabel.font = [UIFont piwigoFontNormal];
    self.rightLabel.font = [UIFont piwigoFontNormal];
    [self paletteChanged];
}

-(void)paletteChanged
{
    self.leftLabel.textColor = [UIColor piwigoLeftLabelColor];
    self.rightLabel.textColor = [UIColor piwigoRightLabelColor];
    self.rightLabel.backgroundColor = [UIColor piwigoCellBackgroundColor];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    // Configure the view for the selected state
	
}

-(void)setPrivacyLevel:(kPiwigoPrivacy)privacy
{
	self.rightLabel.text = [[Model sharedInstance] getNameForPrivacyLevel:privacy];
}

-(void)setLeftLabelText:(NSString*)text
{
	self.leftLabel.text = text;
}

@end
